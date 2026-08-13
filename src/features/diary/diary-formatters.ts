import type { MealType } from '@/domain/diary/diary-entry'
import type { Nutrition } from '@/domain/nutrition/nutrition'
import { fromLocalDateKey } from '@/shared/utils/local-date-key'

const mealTypeLabels: Record<MealType, string> = {
  breakfast: 'Завтрак',
  lunch: 'Обед',
  dinner: 'Ужин',
  snack: 'Перекусы',
}

export const mealTypes: MealType[] = ['breakfast', 'lunch', 'dinner', 'snack']

export function getMealTypeLabel(mealType: MealType): string {
  return mealTypeLabels[mealType]
}

export function formatDiaryNumber(value: number): string {
  return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1 }).format(value)
}

export function formatDiaryDate(dateKey: string): string {
  const formatted = new Intl.DateTimeFormat('ru-RU', {
    weekday: 'short',
    day: 'numeric',
    month: 'long',
  }).format(fromLocalDateKey(dateKey))

  return formatted.charAt(0).toUpperCase() + formatted.slice(1)
}

export function formatDiaryNutrition(nutrition: Nutrition): string {
  return `${formatDiaryNumber(nutrition.calories)} ккал · Б ${formatDiaryNumber(nutrition.protein)} · Ж ${formatDiaryNumber(nutrition.fat)} · У ${formatDiaryNumber(nutrition.carbs)}`
}
