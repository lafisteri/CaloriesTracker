import type { WeeklyGoal } from '@/domain/goals/weekly-goal'

export interface GoalRepository {
  save(goal: WeeklyGoal): Promise<void>
  getById(id: string): Promise<WeeklyGoal | undefined>
  getAll(): Promise<WeeklyGoal[]>
  getEffectiveOn(date: string): Promise<WeeklyGoal | undefined>
}
