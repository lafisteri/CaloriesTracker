import { nutritionCalculator } from '@/domain/nutrition/nutrition-calculator'
import type { Nutrition } from '@/domain/nutrition/nutrition'
import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'
import { recipeCalculator } from '@/domain/recipes/recipe-calculator'
import type { RecipeIngredient } from '@/domain/recipes/recipe-ingredient'
import type { Recipe } from '@/domain/recipes/recipe'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'
import type { ProductRepository } from '@/domain/repositories/product-repository'
import type { RecipeRepository } from '@/domain/repositories/recipe-repository'
import { resolveDiaryUnit } from '@/domain/diary/diary-unit'
import { toServingUnitValue } from '@/domain/diary/diary-unit'
import { unitConverter } from '@/domain/units/unit-converter'
import { createUuid } from '@/shared/utils/create-uuid'

export interface RecipeIngredientDraft {
  id?: string
  productId: string
  productVersionId: string
  amount: number
  unit: string
}

export interface RecipeDraft {
  name: string
  ingredients: RecipeIngredientDraft[]
  cookedWeight?: number
  servingsCount?: number
}

export interface RecipeListItem {
  recipe: Recipe
  currentVersion: RecipeVersion
}

export interface RecipeIngredientDetails {
  ingredient: RecipeIngredient
  product?: Product
  productVersion?: ProductVersion
  nutrition: Nutrition
}

export interface RecipeVersionDetails {
  version: RecipeVersion
  ingredients: RecipeIngredientDetails[]
  per100g?: Nutrition
  perServing?: Nutrition
}

export interface RecipeDetails extends RecipeListItem {
  versions: RecipeVersion[]
  currentVersionDetails: RecipeVersionDetails
  outdatedIngredients: OutdatedRecipeIngredient[]
}

export interface RecipePreview {
  ingredients: RecipeIngredientDetails[]
  total: Nutrition
  per100g?: Nutrition
  perServing?: Nutrition
}

export interface OutdatedRecipeIngredient {
  ingredient: RecipeIngredient
  product: Product
  currentVersion: ProductVersion
  canUpdate: boolean
}

/** Application service for immutable recipe versions and ProductVersion-pinned ingredients. */
export class RecipeService {
  constructor(
    private readonly recipeRepository: RecipeRepository,
    private readonly productRepository: ProductRepository,
  ) {}

  async search(query = ''): Promise<RecipeListItem[]> {
    const normalizedQuery = query.trim().toLocaleLowerCase()
    const recipes = await this.recipeRepository.getActive()
    const matches = recipes.filter((recipe) => normalizedQuery.length === 0 || recipe.name.toLocaleLowerCase().includes(normalizedQuery))

    return this.resolveCurrentRecipes(matches)
  }

  async getById(id: string): Promise<RecipeDetails | undefined> {
    const recipe = await this.recipeRepository.getById(id)

    if (recipe === undefined || recipe.deletedAt !== undefined) {
      return undefined
    }

    const [currentVersion, versions] = await Promise.all([
      this.recipeRepository.getVersionById(recipe.currentVersionId),
      this.recipeRepository.getVersions(recipe.id),
    ])

    if (currentVersion === undefined) {
      return undefined
    }

    const currentVersionDetails = await this.getVersionDetails(currentVersion)
    const outdatedIngredients = await this.getOutdatedIngredients(currentVersion)

    return { recipe, currentVersion, versions, currentVersionDetails, outdatedIngredients }
  }

  async getVersionDetails(version: RecipeVersion): Promise<RecipeVersionDetails> {
    const ingredients = await Promise.all(version.ingredients.map((ingredient) => this.getIngredientDetails(ingredient)))
    const total = recipeNutrition(version)

    return {
      version,
      ingredients,
      per100g: version.cookedWeight === undefined ? undefined : recipeCalculator.calculatePer100g(total, version.cookedWeight),
      perServing: version.servingsCount === undefined ? undefined : recipeCalculator.calculatePerServing(total, version.servingsCount),
    }
  }

  async preview(draft: RecipeDraft): Promise<RecipePreview> {
    const ingredients = await Promise.all(draft.ingredients.map((ingredient) => this.resolveIngredient(ingredient)))
    const total = recipeCalculator.calculateTotalNutrition(ingredients.map((ingredient) => ingredient.nutrition))

    return {
      ingredients,
      total,
      per100g: draft.cookedWeight === undefined ? undefined : recipeCalculator.calculatePer100g(total, draft.cookedWeight),
      perServing: draft.servingsCount === undefined ? undefined : recipeCalculator.calculatePerServing(total, draft.servingsCount),
    }
  }

  async create(draft: RecipeDraft): Promise<RecipeDetails> {
    assertRecipeName(draft.name)
    assertRecipeNormalization(draft)
    const preview = await this.preview(draft)
    assertIngredients(preview.ingredients)
    const now = new Date().toISOString()
    const recipeId = createUuid()
    const version = createRecipeVersion(recipeId, 1, preview, draft, now)
    const recipe: Recipe = {
      id: recipeId,
      name: draft.name.trim(),
      currentVersionId: version.id,
      createdAt: now,
      updatedAt: now,
    }

    await this.recipeRepository.create(recipe, version)

    return this.getById(recipeId).then((details) => {
      if (details === undefined) {
        throw new RecipeNotFoundError()
      }
      return details
    })
  }

  async update(id: string, draft: RecipeDraft): Promise<RecipeDetails> {
    assertRecipeName(draft.name)
    assertRecipeNormalization(draft)
    const details = await this.getById(id)

    if (details === undefined) {
      throw new RecipeNotFoundError()
    }

    const preview = await this.preview(draft)
    assertIngredients(preview.ingredients)
    const now = new Date().toISOString()
    const updatedRecipe: Recipe = {
      ...details.recipe,
      name: draft.name.trim(),
      updatedAt: now,
    }

    if (!hasVersionChanged(details.currentVersion, draft, preview.ingredients)) {
      await this.recipeRepository.save(updatedRecipe)
    } else {
      const version = createRecipeVersion(updatedRecipe.id, details.currentVersion.versionNumber + 1, preview, draft, now)
      updatedRecipe.currentVersionId = version.id
      await this.recipeRepository.saveVersionAndUpdateRecipe(updatedRecipe, version)
    }

    const updatedDetails = await this.getById(id)

    if (updatedDetails === undefined) {
      throw new RecipeNotFoundError()
    }

    return updatedDetails
  }

  async updateIngredients(id: string): Promise<RecipeDetails> {
    const details = await this.getById(id)

    if (details === undefined) {
      throw new RecipeNotFoundError()
    }

    const updates = new Map(details.outdatedIngredients.map(({ ingredient, currentVersion }) => [ingredient.id, currentVersion]))
    const ingredients = await Promise.all(details.currentVersion.ingredients.map(async (ingredient) => {
      const currentVersion = updates.get(ingredient.id)

      if (currentVersion === undefined) {
        return toIngredientDraft(ingredient)
      }

      const previousVersion = await this.productRepository.getVersionById(ingredient.productVersionId)
      const unit = previousVersion === undefined
        ? undefined
        : getEquivalentIngredientUnit(ingredient.unit, previousVersion, currentVersion)

      // A product may have removed or fundamentally changed an old unit. Keep that
      // ingredient pinned to its old ProductVersion until the user replaces it manually.
      return unit === undefined
        ? toIngredientDraft(ingredient)
        : { ...toIngredientDraft(ingredient), productVersionId: currentVersion.id, unit }
    }))

    if (ingredients.every((ingredient, index) => ingredient.productVersionId === details.currentVersion.ingredients[index].productVersionId)) {
      return details
    }

    return this.update(id, {
      name: details.recipe.name,
      cookedWeight: details.currentVersion.cookedWeight,
      servingsCount: details.currentVersion.servingsCount,
      ingredients,
    })
  }

  async softDelete(id: string): Promise<void> {
    const recipe = await this.recipeRepository.getById(id)

    if (recipe === undefined || recipe.deletedAt !== undefined) {
      throw new RecipeNotFoundError()
    }

    await this.recipeRepository.softDelete(id, new Date().toISOString())
  }

  private async resolveCurrentRecipes(recipes: Recipe[]): Promise<RecipeListItem[]> {
    const items = await Promise.all(recipes.map(async (recipe) => {
      const currentVersion = await this.recipeRepository.getVersionById(recipe.currentVersionId)
      return currentVersion === undefined ? undefined : { recipe, currentVersion }
    }))

    return items.filter((item): item is RecipeListItem => item !== undefined)
  }

  private async getIngredientDetails(ingredient: RecipeIngredient): Promise<RecipeIngredientDetails> {
    const [product, productVersion] = await Promise.all([
      this.productRepository.getById(ingredient.productId),
      this.productRepository.getVersionById(ingredient.productVersionId),
    ])

    if (productVersion === undefined || productVersion.productId !== ingredient.productId) {
      return { ingredient, product, productVersion, nutrition: emptyNutrition() }
    }

    return {
      ingredient,
      product,
      productVersion,
      nutrition: calculateIngredientNutrition(productVersion, ingredient.amount, ingredient.unit),
    }
  }

  private async resolveIngredient(draft: RecipeIngredientDraft): Promise<RecipeIngredientDetails> {
    assertPositiveAmount(draft.amount)
    const [product, productVersion] = await Promise.all([
      this.productRepository.getById(draft.productId),
      this.productRepository.getVersionById(draft.productVersionId),
    ])

    if (product === undefined || productVersion === undefined || productVersion.productId !== product.id) {
      throw new RecipeIngredientNotFoundError()
    }

    const normalizedAmount = normalizeIngredientAmount(productVersion, draft.amount, draft.unit)
    const ingredient: RecipeIngredient = {
      id: draft.id ?? createUuid(),
      productId: product.id,
      productVersionId: productVersion.id,
      amount: draft.amount,
      unit: draft.unit,
      normalizedAmount,
    }

    return { ingredient, product, productVersion, nutrition: nutritionCalculator.calculateForProduct(productVersion, normalizedAmount) }
  }

  private async getOutdatedIngredients(version: RecipeVersion): Promise<OutdatedRecipeIngredient[]> {
    const updates = await Promise.all(version.ingredients.map(async (ingredient) => {
      const product = await this.productRepository.getById(ingredient.productId)

      if (product === undefined || product.deletedAt !== undefined || product.currentVersionId === ingredient.productVersionId) {
        return undefined
      }

      const [previousVersion, currentVersion] = await Promise.all([
        this.productRepository.getVersionById(ingredient.productVersionId),
        this.productRepository.getVersionById(product.currentVersionId),
      ])

      return currentVersion === undefined
        ? undefined
        : {
          ingredient,
          product,
          currentVersion,
          canUpdate: previousVersion !== undefined && getEquivalentIngredientUnit(ingredient.unit, previousVersion, currentVersion) !== undefined,
        }
    }))

    return updates.filter((update): update is OutdatedRecipeIngredient => update !== undefined)
  }
}

export class RecipeNotFoundError extends Error {
  constructor() {
    super('Recipe not found.')
    this.name = 'RecipeNotFoundError'
  }
}

export class RecipeIngredientNotFoundError extends Error {
  constructor() {
    super('Recipe ingredient product version not found.')
    this.name = 'RecipeIngredientNotFoundError'
  }
}

export class InvalidRecipeError extends Error {
  constructor() {
    super('Recipe must have a name, ingredients, and at least one output unit.')
    this.name = 'InvalidRecipeError'
  }
}

function createRecipeVersion(recipeId: string, versionNumber: number, preview: RecipePreview, draft: RecipeDraft, createdAt: string): RecipeVersion {
  return {
    id: createUuid(),
    recipeId,
    versionNumber,
    ingredients: preview.ingredients.map(({ ingredient }) => ingredient),
    totalCalories: preview.total.calories,
    totalProtein: preview.total.protein,
    totalFat: preview.total.fat,
    totalCarbs: preview.total.carbs,
    cookedWeight: draft.cookedWeight,
    servingsCount: draft.servingsCount,
    createdAt,
  }
}

function recipeNutrition(version: RecipeVersion): Nutrition {
  return {
    calories: version.totalCalories,
    protein: version.totalProtein,
    fat: version.totalFat,
    carbs: version.totalCarbs,
  }
}

function calculateIngredientNutrition(version: ProductVersion, amount: number, unit: string): Nutrition {
  return nutritionCalculator.calculateForProduct(version, normalizeIngredientAmount(version, amount, unit))
}

function normalizeIngredientAmount(version: ProductVersion, amount: number, unit: string): number {
  const resolvedUnit = resolveDiaryUnit(version, unit)
  return resolvedUnit.type === 'base' ? amount : unitConverter.toBaseAmount(version, amount, resolvedUnit.servingUnit!)
}

function emptyNutrition(): Nutrition {
  return { calories: 0, protein: 0, fat: 0, carbs: 0 }
}

function assertRecipeName(name: string): void {
  if (name.trim().length === 0) {
    throw new InvalidRecipeError()
  }
}

function assertRecipeNormalization(draft: RecipeDraft): void {
  const values = [draft.cookedWeight, draft.servingsCount].filter((value): value is number => value !== undefined)

  if (values.some((value) => !Number.isFinite(value) || value <= 0) || values.length === 0) {
    throw new InvalidRecipeError()
  }

  if (draft.servingsCount !== undefined && !Number.isInteger(draft.servingsCount)) {
    throw new InvalidRecipeError()
  }
}

function assertIngredients(ingredients: RecipeIngredientDetails[]): void {
  if (ingredients.length === 0) {
    throw new InvalidRecipeError()
  }
}

function assertPositiveAmount(amount: number): void {
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new InvalidRecipeError()
  }
}

function hasVersionChanged(current: RecipeVersion, draft: RecipeDraft, ingredients: RecipeIngredientDetails[]): boolean {
  return current.cookedWeight !== draft.cookedWeight
    || current.servingsCount !== draft.servingsCount
    || current.ingredients.length !== ingredients.length
    || current.ingredients.some((ingredient, index) => {
      const next = ingredients[index].ingredient
      return ingredient.productId !== next.productId
        || ingredient.productVersionId !== next.productVersionId
        || ingredient.amount !== next.amount
        || ingredient.unit !== next.unit
        || ingredient.normalizedAmount !== next.normalizedAmount
    })
}

function toIngredientDraft(ingredient: RecipeIngredient): RecipeIngredientDraft {
  return {
    id: ingredient.id,
    productId: ingredient.productId,
    productVersionId: ingredient.productVersionId,
    amount: ingredient.amount,
    unit: ingredient.unit,
  }
}

/**
 * Serving-unit ids are intentionally local to ProductVersion. Match a serving
 * by its human-readable identity when carrying an ingredient to a new version.
 */
function getEquivalentIngredientUnit(unit: string, previousVersion: ProductVersion, currentVersion: ProductVersion): string | undefined {
  try {
    const resolvedUnit = resolveDiaryUnit(previousVersion, unit)

    if (resolvedUnit.type === 'base') {
      return previousVersion.baseUnitType === currentVersion.baseUnitType ? currentVersion.baseUnitType : undefined
    }

    const previousServingUnit = resolvedUnit.servingUnit!
    const currentServingUnit = currentVersion.servingUnits.find((candidate) => candidate.name === previousServingUnit.name)

    return currentServingUnit === undefined ? undefined : toServingUnitValue(currentServingUnit)
  } catch {
    return undefined
  }
}
