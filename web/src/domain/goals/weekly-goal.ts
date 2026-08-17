export interface DailyMacroGoal {
  calories: number
  protein: number
  fat: number
  carbs: number
}

export const weeklyGoalDays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
] as const

export type WeeklyGoalDay = (typeof weeklyGoalDays)[number]
export type WeeklyGoalsByDay = Record<WeeklyGoalDay, DailyMacroGoal>

export interface WeeklyGoal {
  id: string
  effectiveFrom: string
  monday: DailyMacroGoal
  tuesday: DailyMacroGoal
  wednesday: DailyMacroGoal
  thursday: DailyMacroGoal
  friday: DailyMacroGoal
  saturday: DailyMacroGoal
  sunday: DailyMacroGoal
  createdAt: string
}
