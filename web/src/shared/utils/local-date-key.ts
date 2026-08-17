const dateKeyPattern = /^\d{4}-\d{2}-\d{2}$/

/** Returns the user's local calendar day without converting through UTC. */
export function toLocalDateKey(date: Date = new Date()): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')

  return `${year}-${month}-${day}`
}

export function isLocalDateKey(value: string): boolean {
  if (!dateKeyPattern.test(value)) {
    return false
  }

  const [year, month, day] = value.split('-').map(Number)
  const date = new Date(year, month - 1, day)

  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day
}

export function shiftLocalDateKey(dateKey: string, days: number): string {
  const date = fromLocalDateKey(dateKey)
  date.setDate(date.getDate() + days)

  return toLocalDateKey(date)
}

export function fromLocalDateKey(dateKey: string): Date {
  if (!isLocalDateKey(dateKey)) {
    throw new Error('Date key must use the YYYY-MM-DD local date format.')
  }

  const [year, month, day] = dateKey.split('-').map(Number)

  return new Date(year, month - 1, day, 12)
}
