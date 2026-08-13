export interface DailyMacroGoal {
  calories: number
  protein: number
  fat: number
  carbs: number
}

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
