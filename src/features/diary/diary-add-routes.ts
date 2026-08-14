import type { MealType } from '@/domain/diary/diary-entry'
import { isLocalDateKey } from '@/shared/utils/local-date-key'

const mealTypes: MealType[] = ['breakfast', 'lunch', 'dinner', 'snack']

export interface DiaryAddContext {
  date: string
  mealType: MealType
}

export function getDiaryAddContext(date: string | undefined, mealType: string | undefined): DiaryAddContext | undefined {
  if (date === undefined || mealType === undefined || !isLocalDateKey(date) || !mealTypes.includes(mealType as MealType)) {
    return undefined
  }

  return { date, mealType: mealType as MealType }
}

export function getDiaryPath(date: string): string {
  return `/diary?date=${encodeURIComponent(date)}`
}

export function getDiaryDateFromSearch(search: string): string | undefined {
  const date = new URLSearchParams(search).get('date')

  return date !== null && isLocalDateKey(date) ? date : undefined
}

export function getDiaryAddSelectionPath(context: DiaryAddContext): string {
  return `/diary/${context.date}/${context.mealType}/add`
}

export function getDiaryAddAmountPath(context: DiaryAddContext, productId: string): string {
  return `${getDiaryAddSelectionPath(context)}/${encodeURIComponent(productId)}`
}

export function getDiaryAddSelectionPathFromReturnTo(returnTo: string | null): string | undefined {
  if (returnTo === null) {
    return undefined
  }

  const match = /^\/diary\/(\d{4}-\d{2}-\d{2})\/(breakfast|lunch|dinner|snack)\/add$/.exec(returnTo)
  const context = match === null ? undefined : getDiaryAddContext(match[1], match[2])

  return context === undefined ? undefined : getDiaryAddSelectionPath(context)
}
