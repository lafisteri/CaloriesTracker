export function isPositiveDiaryAmount(value: string): boolean {
  const amount = Number(value)

  return Number.isFinite(amount) && amount > 0
}
