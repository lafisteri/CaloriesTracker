import type { DayStats, MacroDistribution, WeeklyCalorieBalance } from '@/application/statistics/statistics-service'

export const weekDayShortLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'] as const

export function formatDashboardNumber(value: number): string {
  return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1 }).format(value)
}

export function formatWeeklyBalance(balance: WeeklyCalorieBalance): string {
  if (balance.difference === 0) {
    return 'В цели за неделю'
  }

  return balance.difference < 0
    ? `−${formatDashboardNumber(Math.abs(balance.difference))} ккал за неделю`
    : `+${formatDashboardNumber(balance.difference)} ккал к недельной цели`
}

export function formatMacroDistribution(distribution: MacroDistribution): string {
  return `Б ${formatDashboardNumber(distribution.protein)}% · Ж ${formatDashboardNumber(distribution.fat)}% · У ${formatDashboardNumber(distribution.carbs)}%`
}

export function getCalorieBarState(day: DayStats): 'empty' | 'no-goal' | 'below' | 'near-goal' | 'over' {
  const target = day.goal?.calories

  if (target === undefined || target === 0) {
    return 'no-goal'
  }

  if (day.calories === 0) {
    return 'empty'
  }

  const ratio = day.calories / target

  if (ratio > 1.05) {
    return 'over'
  }

  return ratio >= 0.9 ? 'near-goal' : 'below'
}

export function getCalorieBarHeight(day: DayStats): number {
  const target = day.goal?.calories

  if (target === undefined || target === 0) {
    return 0
  }

  return Math.min(day.calories / target * 100, 150) / 150 * 100
}

export function getCalorieBarLabel(day: DayStats): string {
  const target = day.goal?.calories

  if (target === undefined || target === 0) {
    return `${formatDashboardNumber(day.calories)} ккал, цель не задана`
  }

  if (day.calories === 0) {
    return `Нет записей, цель ${formatDashboardNumber(target)} ккал`
  }

  return `${formatDashboardNumber(day.calories)} из ${formatDashboardNumber(target)} ккал, ${formatDashboardNumber(day.calories / target * 100)}% цели`
}
