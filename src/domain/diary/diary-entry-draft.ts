import type { MealType } from './diary-entry'

export interface CreateProductDiaryEntryDraft {
  date: string
  mealType: MealType
  productId: string
  amount: number
  unit: string
}

export interface CreateRecipeDiaryEntryDraft {
  date: string
  mealType: MealType
  recipeId: string
  amount: number
  unit: string
}

export interface UpdateDiaryEntryDraft {
  mealType: MealType
  amount: number
  unit: string
}
