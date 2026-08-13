import type { DiaryEntry, MealType } from '@/domain/diary/diary-entry'
import type { CreateProductDiaryEntryDraft, UpdateDiaryEntryDraft } from '@/domain/diary/diary-entry-draft'
import { getDiaryUnitOptions, resolveDiaryUnit, type DiaryUnitOption } from '@/domain/diary/diary-unit'
import { nutritionCalculator } from '@/domain/nutrition/nutrition-calculator'
import type { Nutrition } from '@/domain/nutrition/nutrition'
import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'
import type { DiaryRepository } from '@/domain/repositories/diary-repository'
import type { ProductRepository } from '@/domain/repositories/product-repository'
import { unitConverter } from '@/domain/units/unit-converter'
import { createUuid } from '@/shared/utils/create-uuid'
import { isLocalDateKey } from '@/shared/utils/local-date-key'

const mealTypes: MealType[] = ['breakfast', 'lunch', 'dinner', 'snack']

export interface DiaryProduct {
  product: Product
  currentVersion: ProductVersion
}

export interface DiaryEntryDetails {
  entry: DiaryEntry
  sourceVersion: ProductVersion
  unitOptions: DiaryUnitOption[]
}

export interface DiaryDay {
  date: string
  entries: DiaryEntry[]
  totals: Nutrition
  meals: Record<MealType, DiaryMeal>
}

export interface DiaryMeal {
  entries: DiaryEntryListItem[]
  totals: Nutrition
}

export interface DiaryEntryListItem {
  entry: DiaryEntry
  unitLabel: string
}

/** Application service that maintains immutable nutrition snapshots for diary history. */
export class DiaryService {
  constructor(
    private readonly diaryRepository: DiaryRepository,
    private readonly productRepository: ProductRepository,
  ) {}

  async getDay(date: string): Promise<DiaryDay> {
    assertDateKey(date)
    const entries = await this.diaryRepository.getEntriesByDate(date)
    const entryItems = await Promise.all(entries.map(async (entry) => ({
      entry,
      unitLabel: await this.getEntryUnitLabel(entry),
    })))

    return {
      date,
      entries,
      totals: sumNutrition(entries),
      meals: mealTypes.reduce<Record<MealType, DiaryMeal>>((meals, mealType) => {
        const mealEntries = entries.filter((entry) => entry.mealType === mealType)
        meals[mealType] = {
          entries: entryItems.filter((item) => item.entry.mealType === mealType),
          totals: sumNutrition(mealEntries),
        }
        return meals
      }, {} as Record<MealType, DiaryMeal>),
    }
  }

  async getEntryDetails(id: string): Promise<DiaryEntryDetails | undefined> {
    const entry = await this.diaryRepository.getEntryById(id)

    if (entry === undefined || entry.deletedAt !== undefined || entry.sourceType !== 'product') {
      return undefined
    }

    const sourceVersion = await this.productRepository.getVersionById(entry.sourceVersionId)

    if (sourceVersion === undefined) {
      throw new DiaryEntrySourceNotFoundError()
    }

    return { entry, sourceVersion, unitOptions: getDiaryUnitOptions(sourceVersion) }
  }

  async searchProducts(query = ''): Promise<DiaryProduct[]> {
    const normalizedQuery = query.trim().toLocaleLowerCase()
    const products = await this.productRepository.getActive()
    const matches = products.filter((product) => normalizedQuery.length === 0
      || product.name.toLocaleLowerCase().includes(normalizedQuery)
      || product.barcode?.includes(query.trim()) === true)

    return this.resolveCurrentProducts(matches)
  }

  async getRecentProducts(limit = 10): Promise<DiaryProduct[]> {
    const entries = await this.diaryRepository.getRecentProductEntries()
    const sourceIds = [...new Set(entries.map((entry) => entry.sourceId))].slice(0, limit)
    const products = await Promise.all(sourceIds.map((id) => this.productRepository.getById(id)))

    return this.resolveCurrentProducts(products.filter((product): product is Product => product !== undefined && product.deletedAt === undefined))
  }

  previewProduct(product: DiaryProduct, amount: number, unit: string): Nutrition {
    return calculateSnapshot(product.currentVersion, amount, unit)
  }

  previewEntry(details: DiaryEntryDetails, amount: number, unit: string): Nutrition {
    return calculateSnapshot(details.sourceVersion, amount, unit)
  }

  async addProduct(draft: CreateProductDiaryEntryDraft): Promise<DiaryEntry> {
    assertDateKey(draft.date)
    assertMealType(draft.mealType)
    assertPositiveAmount(draft.amount)

    const product = await this.productRepository.getById(draft.productId)

    if (product === undefined || product.deletedAt !== undefined) {
      throw new DiaryProductNotFoundError()
    }

    const sourceVersion = await this.productRepository.getVersionById(product.currentVersionId)

    if (sourceVersion === undefined) {
      throw new DiaryEntrySourceNotFoundError()
    }

    const nutrition = calculateSnapshot(sourceVersion, draft.amount, draft.unit)
    const now = new Date().toISOString()
    const entry: DiaryEntry = {
      id: createUuid(),
      date: draft.date,
      mealType: draft.mealType,
      sourceType: 'product',
      sourceId: product.id,
      sourceVersionId: sourceVersion.id,
      sourceName: product.name,
      amount: draft.amount,
      unit: draft.unit,
      ...nutrition,
      createdAt: now,
      updatedAt: now,
    }

    await this.diaryRepository.createEntry(entry)

    return entry
  }

  async updateEntry(id: string, draft: UpdateDiaryEntryDraft): Promise<DiaryEntry> {
    assertMealType(draft.mealType)
    assertPositiveAmount(draft.amount)
    const details = await this.getEntryDetails(id)

    if (details === undefined) {
      throw new DiaryEntryNotFoundError()
    }

    const nutrition = details.entry.amount === draft.amount && details.entry.unit === draft.unit
      ? getEntryNutritionSnapshot(details.entry)
      : this.previewEntry(details, draft.amount, draft.unit)
    const entry: DiaryEntry = {
      ...details.entry,
      mealType: draft.mealType,
      amount: draft.amount,
      unit: draft.unit,
      ...nutrition,
      updatedAt: new Date().toISOString(),
    }

    await this.diaryRepository.updateEntry(entry)

    return entry
  }

  async softDeleteEntry(id: string): Promise<void> {
    const entry = await this.diaryRepository.getEntryById(id)

    if (entry === undefined || entry.deletedAt !== undefined) {
      throw new DiaryEntryNotFoundError()
    }

    await this.diaryRepository.softDeleteEntry(id, new Date().toISOString())
  }

  private async resolveCurrentProducts(products: Product[]): Promise<DiaryProduct[]> {
    const productResults = await Promise.all(products.map(async (product) => {
      const currentVersion = await this.productRepository.getVersionById(product.currentVersionId)
      return currentVersion === undefined ? undefined : { product, currentVersion }
    }))

    return productResults.filter((result): result is DiaryProduct => result !== undefined)
  }

  private async getEntryUnitLabel(entry: DiaryEntry): Promise<string> {
    if (entry.sourceType !== 'product') {
      return entry.unit
    }

    const sourceVersion = await this.productRepository.getVersionById(entry.sourceVersionId)

    if (sourceVersion === undefined) {
      return entry.unit
    }

    try {
      return resolveDiaryUnit(sourceVersion, entry.unit).label
    } catch {
      return entry.unit
    }
  }
}

export class DiaryEntryNotFoundError extends Error {
  constructor() {
    super('Diary entry not found.')
    this.name = 'DiaryEntryNotFoundError'
  }
}

export class DiaryEntrySourceNotFoundError extends Error {
  constructor() {
    super('Diary entry source version not found.')
    this.name = 'DiaryEntrySourceNotFoundError'
  }
}

export class DiaryProductNotFoundError extends Error {
  constructor() {
    super('Product not found.')
    this.name = 'DiaryProductNotFoundError'
  }
}

function calculateSnapshot(version: ProductVersion, amount: number, unit: string): Nutrition {
  assertPositiveAmount(amount)
  const resolvedUnit = resolveDiaryUnit(version, unit)
  const normalizedAmount = resolvedUnit.type === 'base'
    ? amount
    : unitConverter.toBaseAmount(version, amount, resolvedUnit.servingUnit!)

  return nutritionCalculator.calculateForProduct(version, normalizedAmount)
}

function sumNutrition(entries: DiaryEntry[]): Nutrition {
  return entries.reduce<Nutrition>((total, entry) => ({
    calories: total.calories + entry.calories,
    protein: total.protein + entry.protein,
    fat: total.fat + entry.fat,
    carbs: total.carbs + entry.carbs,
  }), createEmptyNutrition())
}

function getEntryNutritionSnapshot(entry: DiaryEntry): Nutrition {
  return {
    calories: entry.calories,
    protein: entry.protein,
    fat: entry.fat,
    carbs: entry.carbs,
  }
}

function createEmptyNutrition(): Nutrition {
  return { calories: 0, protein: 0, fat: 0, carbs: 0 }
}

function assertDateKey(date: string): void {
  if (!isLocalDateKey(date)) {
    throw new Error('Diary date must be a valid local date key.')
  }
}

function assertMealType(mealType: string): asserts mealType is MealType {
  if (!mealTypes.includes(mealType as MealType)) {
    throw new Error('Unknown meal type.')
  }
}

function assertPositiveAmount(amount: number): void {
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error('Diary amount must be a positive finite number.')
  }
}
