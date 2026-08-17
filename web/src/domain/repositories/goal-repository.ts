import type { WeeklyGoal } from '@/domain/goals/weekly-goal'

export interface GoalRepository {
  /** Returns false when a goal already starts on the same effective date. */
  create(goal: WeeklyGoal): Promise<boolean>
  getById(id: string): Promise<WeeklyGoal | undefined>
  getAll(): Promise<WeeklyGoal[]>
  getLatest(): Promise<WeeklyGoal | undefined>
  getEffectiveOn(date: string): Promise<WeeklyGoal | undefined>
  getEffectiveOnDates(dates: string[]): Promise<Record<string, WeeklyGoal | undefined>>
}
