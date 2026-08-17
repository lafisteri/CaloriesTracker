import { fromLocalDateKey, shiftLocalDateKey } from './local-date-key'

/** Returns the Monday-to-Sunday local date keys for the week containing dateKey. */
export function getWeekRange(dateKey: string): string[] {
  const date = fromLocalDateKey(dateKey)
  const daysSinceMonday = (date.getDay() + 6) % 7
  const monday = shiftLocalDateKey(dateKey, -daysSinceMonday)

  return Array.from({ length: 7 }, (_, index) => shiftLocalDateKey(monday, index))
}
