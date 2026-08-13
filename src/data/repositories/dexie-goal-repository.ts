import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'
import type { WeeklyGoal } from '@/domain/goals/weekly-goal'
import type { GoalRepository } from '@/domain/repositories/goal-repository'

export class DexieGoalRepository implements GoalRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  async save(goal: WeeklyGoal): Promise<void> {
    await this.database.weeklyGoals.put(goal)
  }

  getById(id: string): Promise<WeeklyGoal | undefined> {
    return this.database.weeklyGoals.get(id)
  }

  getAll(): Promise<WeeklyGoal[]> {
    return this.database.weeklyGoals.orderBy('effectiveFrom').reverse().toArray()
  }

  async getEffectiveOn(date: string): Promise<WeeklyGoal | undefined> {
    return this.database.weeklyGoals.where('effectiveFrom').belowOrEqual(date).last()
  }
}
