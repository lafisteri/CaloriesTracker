import type { DiaryEntry, DiarySourceType, MealType } from '@/domain/diary/diary-entry'
import type { CreateProductDiaryEntryDraft, CreateRecipeDiaryEntryDraft, UpdateDiaryEntryDraft } from '@/domain/diary/diary-entry-draft'
import { getDiaryUnitOptions, resolveDiaryUnit, type DiaryUnitOption } from '@/domain/diary/diary-unit'
import { nutritionCalculator } from '@/domain/nutrition/nutrition-calculator'
import type { Nutrition } from '@/domain/nutrition/nutrition'
import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'
import { normalizeBarcode } from '@/domain/products/barcode'
import type { DiaryRepository } from '@/domain/repositories/diary-repository'
import type { ProductRepository } from '@/domain/repositories/product-repository'
import type { Recipe } from '@/domain/recipes/recipe'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'
import type { RecipeRepository } from '@/domain/repositories/recipe-repository'
import { recipeCalculator } from '@/domain/recipes/recipe-calculator'
import { unitConverter } from '@/domain/units/unit-converter'
import { createUuid } from '@/shared/utils/create-uuid'
import { isLocalDateKey } from '@/shared/utils/local-date-key'

const mealTypes: MealType[] = ['breakfast', 'lunch', 'dinner', 'snack']

export interface DiaryProduct {
  product: Product
  currentVersion: ProductVersion
}

export interface DiaryRecipe {
  recipe: Recipe
  currentVersion: RecipeVersion
}

export type DiaryFoodSource = ({ sourceType: 'product' } & DiaryProduct) | ({ sourceType: 'recipe' } & DiaryRecipe)

export type DiaryEntryDetails = ProductDiaryEntryDetails | RecipeDiaryEntryDetails

interface ProductDiaryEntryDetails {
  entry: DiaryEntry & { sourceType: 'product' }
  sourceVersion: ProductVersion
  unitOptions: DiaryUnitOption[]
}

interface RecipeDiaryEntryDetails {
  entry: DiaryEntry & { sourceType: 'recipe' }
  sourceVersion: RecipeVersion
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
    private readonly recipeRepository: RecipeRepository,
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

  /** Returns persisted diary snapshot totals without resolving products or versions. */
  async getTotalsForDate(date: string): Promise<Nutrition> {
    return (await this.getTotalsForDates([date]))[date]
  }

  /** Gets persisted snapshot totals for several dates in one repository query. */
  async getTotalsForDates(dates: string[]): Promise<Record<string, Nutrition>> {
    dates.forEach(assertDateKey)
    const totalsByDate = dates.reduce<Record<string, Nutrition>>((totals, date) => {
      totals[date] = createEmptyNutrition()
      return totals
    }, {})
    const entries = await this.diaryRepository.getEntriesByDates(dates)

    entries.forEach((entry) => {
      totalsByDate[entry.date] = addNutrition(totalsByDate[entry.date], entry)
    })

    return totalsByDate
  }

  async getEntryDetails(id: string): Promise<DiaryEntryDetails | undefined> {
    const entry = await this.diaryRepository.getEntryById(id)

    if (entry === undefined || entry.deletedAt !== undefined) {
      return undefined
    }

    if (entry.sourceType === 'recipe') {
      const sourceVersion = await this.recipeRepository.getVersionById(entry.sourceVersionId)

      if (sourceVersion === undefined) {
        throw new DiaryEntrySourceNotFoundError()
      }

      return { entry: entry as RecipeDiaryEntryDetails['entry'], sourceVersion, unitOptions: getRecipeUnitOptions(sourceVersion) }
    }

    const sourceVersion = await this.productRepository.getVersionById(entry.sourceVersionId)

    if (sourceVersion === undefined) {
      throw new DiaryEntrySourceNotFoundError()
    }

    return { entry: entry as ProductDiaryEntryDetails['entry'], sourceVersion, unitOptions: getDiaryUnitOptions(sourceVersion) }
  }

  async searchProducts(query = ''): Promise<DiaryProduct[]> {
    const normalizedQuery = query.trim().toLocaleLowerCase()
    const normalizedBarcode = normalizeBarcode(query)
    const products = await this.productRepository.getActive()
    const matches = products.filter((product) => normalizedQuery.length === 0
      || product.name.toLocaleLowerCase().includes(normalizedQuery)
      || product.barcode === normalizedBarcode)

    return this.resolveCurrentProducts(matches)
  }

  async searchFoodSources(query = ''): Promise<DiaryFoodSource[]> {
    const [products, recipes] = await Promise.all([
      this.searchProducts(query),
      this.searchRecipes(query),
    ])

    return [
      ...products.map((product): DiaryFoodSource => ({ sourceType: 'product', ...product })),
      ...recipes.map((recipe): DiaryFoodSource => ({ sourceType: 'recipe', ...recipe })),
    ]
  }

  async getRecentProducts(limit = 10): Promise<DiaryProduct[]> {
    const entries = (await this.diaryRepository.getRecentEntries()).filter((entry) => entry.sourceType === 'product')
    const sourceIds = [...new Set(entries.map((entry) => entry.sourceId))].slice(0, limit)
    const products = await Promise.all(sourceIds.map((id) => this.productRepository.getById(id)))

    return this.resolveCurrentProducts(products.filter((product): product is Product => product !== undefined && product.deletedAt === undefined))
  }

  async getRecentFoodSources(limit = 10): Promise<DiaryFoodSource[]> {
    const entries = await this.diaryRepository.getRecentEntries()
    const seenSourceKeys = new Set<string>()
    const sources: DiaryFoodSource[] = []

    for (const entry of entries) {
      const sourceKey = `${entry.sourceType}:${entry.sourceId}`

      if (seenSourceKeys.has(sourceKey)) {
        continue
      }

      seenSourceKeys.add(sourceKey)
      const source = await this.getFoodSource(entry.sourceType, entry.sourceId)

      if (source !== undefined) {
        sources.push(source)
      }

      if (sources.length === limit) {
        break
      }
    }

    return sources
  }

  async getFoodSource(sourceType: DiarySourceType, sourceId: string): Promise<DiaryFoodSource | undefined> {
    if (sourceType === 'product') {
      const product = await this.productRepository.getById(sourceId)

      if (product === undefined || product.deletedAt !== undefined) {
        return undefined
      }

      const currentVersion = await this.productRepository.getVersionById(product.currentVersionId)
      return currentVersion === undefined ? undefined : { sourceType, product, currentVersion }
    }

    const recipe = await this.recipeRepository.getById(sourceId)

    if (recipe === undefined || recipe.deletedAt !== undefined) {
      return undefined
    }

    const currentVersion = await this.recipeRepository.getVersionById(recipe.currentVersionId)
    return currentVersion === undefined ? undefined : { sourceType, recipe, currentVersion }
  }

  getFoodUnitOptions(source: DiaryFoodSource): DiaryUnitOption[] {
    return source.sourceType === 'product' ? getDiaryUnitOptions(source.currentVersion) : getRecipeUnitOptions(source.currentVersion)
  }

  previewFoodSource(source: DiaryFoodSource, amount: number, unit: string): Nutrition {
    return source.sourceType === 'product'
      ? this.previewProduct(source, amount, unit)
      : calculateRecipeSnapshot(source.currentVersion, amount, unit)
  }

  previewProduct(product: DiaryProduct, amount: number, unit: string): Nutrition {
    return calculateSnapshot(product.currentVersion, amount, unit)
  }

  previewEntry(details: DiaryEntryDetails, amount: number, unit: string): Nutrition {
    return isProductEntryDetails(details)
      ? calculateSnapshot(details.sourceVersion, amount, unit)
      : calculateRecipeSnapshot(details.sourceVersion, amount, unit)
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
    const sortOrder = await this.getNextSortOrder(draft.date, draft.mealType)
    const now = new Date().toISOString()
    const entry: DiaryEntry = {
      id: createUuid(),
      date: draft.date,
      mealType: draft.mealType,
      sortOrder,
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

  async addRecipe(draft: CreateRecipeDiaryEntryDraft): Promise<DiaryEntry> {
    assertDateKey(draft.date)
    assertMealType(draft.mealType)
    assertPositiveAmount(draft.amount)
    const recipe = await this.recipeRepository.getById(draft.recipeId)

    if (recipe === undefined || recipe.deletedAt !== undefined) {
      throw new DiaryRecipeNotFoundError()
    }

    const sourceVersion = await this.recipeRepository.getVersionById(recipe.currentVersionId)

    if (sourceVersion === undefined) {
      throw new DiaryEntrySourceNotFoundError()
    }

    const nutrition = calculateRecipeSnapshot(sourceVersion, draft.amount, draft.unit)
    const sortOrder = await this.getNextSortOrder(draft.date, draft.mealType)
    const now = new Date().toISOString()
    const entry: DiaryEntry = {
      id: createUuid(),
      date: draft.date,
      mealType: draft.mealType,
      sortOrder,
      sourceType: 'recipe',
      sourceId: recipe.id,
      sourceVersionId: sourceVersion.id,
      sourceName: recipe.name,
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

  /** Moves an entry within the current day and normalizes affected meal positions. */
  async moveEntry(id: string, targetMealType: MealType, targetIndex: number): Promise<void> {
    assertMealType(targetMealType)

    if (!Number.isInteger(targetIndex) || targetIndex < 0) {
      throw new Error('Diary target index must be a non-negative integer.')
    }

    const entry = await this.diaryRepository.getEntryById(id)

    if (entry === undefined || entry.deletedAt !== undefined) {
      throw new DiaryEntryNotFoundError()
    }

    const entries = await this.diaryRepository.getEntriesByDate(entry.date)
    const sourceEntries = getMealEntries(entries, entry.mealType)
    const targetEntries = entry.mealType === targetMealType ? sourceEntries : getMealEntries(entries, targetMealType)
    const sourceIndex = sourceEntries.findIndex((candidate) => candidate.id === entry.id)

    if (sourceIndex === -1) {
      throw new DiaryEntryNotFoundError()
    }

    const withoutEntry = sourceEntries.filter((candidate) => candidate.id !== entry.id)
    const targetWithoutEntry = entry.mealType === targetMealType
      ? withoutEntry
      : targetEntries
    const insertionIndex = Math.min(targetIndex, targetWithoutEntry.length)
    const reorderedTargetEntries = [...targetWithoutEntry]
    reorderedTargetEntries.splice(insertionIndex, 0, entry)
    const updatedAt = new Date().toISOString()

    const entriesToUpdate = entry.mealType === targetMealType
      ? normalizeMealEntries(reorderedTargetEntries, targetMealType, updatedAt)
      : [
          ...normalizeMealEntries(withoutEntry, entry.mealType, updatedAt),
          ...normalizeMealEntries(reorderedTargetEntries, targetMealType, updatedAt),
        ]

    await this.diaryRepository.updateEntries(entriesToUpdate)
  }

  private async resolveCurrentProducts(products: Product[]): Promise<DiaryProduct[]> {
    const productResults = await Promise.all(products.map(async (product) => {
      const currentVersion = await this.productRepository.getVersionById(product.currentVersionId)
      return currentVersion === undefined ? undefined : { product, currentVersion }
    }))

    return productResults.filter((result): result is DiaryProduct => result !== undefined)
  }

  private async searchRecipes(query: string): Promise<DiaryRecipe[]> {
    const normalizedQuery = query.trim().toLocaleLowerCase()
    const recipes = await this.recipeRepository.getActive()
    const matches = recipes.filter((recipe) => normalizedQuery.length === 0 || recipe.name.toLocaleLowerCase().includes(normalizedQuery))
    const results = await Promise.all(matches.map(async (recipe) => {
      const currentVersion = await this.recipeRepository.getVersionById(recipe.currentVersionId)
      return currentVersion === undefined ? undefined : { recipe, currentVersion }
    }))

    return results.filter((result): result is DiaryRecipe => result !== undefined)
  }

  private async getEntryUnitLabel(entry: DiaryEntry): Promise<string> {
    if (entry.sourceType === 'recipe') {
      return getRecipeUnitLabel(entry.unit)
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

  private async getNextSortOrder(date: string, mealType: MealType): Promise<number> {
    const entries = await this.diaryRepository.getEntriesByDate(date)
    const lastEntry = getMealEntries(entries, mealType).at(-1)

    return lastEntry === undefined ? 0 : lastEntry.sortOrder + 100
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

export class DiaryRecipeNotFoundError extends Error {
  constructor() {
    super('Recipe not found.')
    this.name = 'DiaryRecipeNotFoundError'
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

function getRecipeUnitOptions(version: RecipeVersion): DiaryUnitOption[] {
  const options: DiaryUnitOption[] = []

  if (version.cookedWeight !== undefined) {
    options.push({ value: 'g', label: 'г' })
  }

  if (version.servingsCount !== undefined) {
    options.push({ value: 'piece', label: 'шт' })
  }

  return options
}

function getRecipeUnitLabel(unit: string): string {
  return unit === 'piece' ? 'шт' : unit === 'g' ? 'г' : unit
}

function isProductEntryDetails(details: DiaryEntryDetails): details is ProductDiaryEntryDetails {
  return details.entry.sourceType === 'product'
}

function calculateRecipeSnapshot(version: RecipeVersion, amount: number, unit: string): Nutrition {
  assertPositiveAmount(amount)
  const total = {
    calories: version.totalCalories,
    protein: version.totalProtein,
    fat: version.totalFat,
    carbs: version.totalCarbs,
  }

  if (unit === 'g' && version.cookedWeight !== undefined) {
    return recipeCalculator.scale(total, amount / version.cookedWeight)
  }

  if (unit === 'piece' && version.servingsCount !== undefined) {
    return recipeCalculator.scale(total, amount / version.servingsCount)
  }

  throw new Error('Diary unit is not available for this recipe version.')
}

function sumNutrition(entries: DiaryEntry[]): Nutrition {
  return entries.reduce<Nutrition>(addNutrition, createEmptyNutrition())
}

function addNutrition(total: Nutrition, nutrition: Nutrition): Nutrition {
  return {
    calories: total.calories + nutrition.calories,
    protein: total.protein + nutrition.protein,
    fat: total.fat + nutrition.fat,
    carbs: total.carbs + nutrition.carbs,
  }
}

function getEntryNutritionSnapshot(entry: DiaryEntry): Nutrition {
  return {
    calories: entry.calories,
    protein: entry.protein,
    fat: entry.fat,
    carbs: entry.carbs,
  }
}

function getMealEntries(entries: DiaryEntry[], mealType: MealType): DiaryEntry[] {
  return entries
    .filter((entry) => entry.mealType === mealType)
    .sort(compareDiaryEntries)
}

function normalizeMealEntries(entries: DiaryEntry[], mealType: MealType, updatedAt: string): DiaryEntry[] {
  return entries.map((entry, index) => ({
    ...entry,
    mealType,
    sortOrder: index * 100,
    updatedAt,
  }))
}

function compareDiaryEntries(left: DiaryEntry, right: DiaryEntry): number {
  const sortOrderDifference = left.sortOrder - right.sortOrder

  if (Number.isFinite(sortOrderDifference) && sortOrderDifference !== 0) {
    return sortOrderDifference
  }

  const createdAtDifference = left.createdAt.localeCompare(right.createdAt)
  return createdAtDifference !== 0 ? createdAtDifference : left.id.localeCompare(right.id)
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
