import type { Nutrition } from '@/domain/nutrition/nutrition'

export type DailyMacroGoal = Nutrition

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
