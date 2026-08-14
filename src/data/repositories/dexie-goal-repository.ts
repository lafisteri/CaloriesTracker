import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'
import type { WeeklyGoal } from '@/domain/goals/weekly-goal'
import type { GoalRepository } from '@/domain/repositories/goal-repository'

export class DexieGoalRepository implements GoalRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  create(goal: WeeklyGoal): Promise<boolean> {
    return this.database.transaction('rw', this.database.weeklyGoals, async () => {
      const existingGoal = await this.database.weeklyGoals.where('effectiveFrom').equals(goal.effectiveFrom).first()

      if (existingGoal !== undefined) {
        return false
      }

      await this.database.weeklyGoals.add(goal)

      return true
    })
  }

  getById(id: string): Promise<WeeklyGoal | undefined> {
    return this.database.weeklyGoals.get(id)
  }

  getAll(): Promise<WeeklyGoal[]> {
    return this.database.weeklyGoals.orderBy('effectiveFrom').toArray()
  }

  async getEffectiveOn(date: string): Promise<WeeklyGoal | undefined> {
    return (await this.getEffectiveOnDates([date]))[date]
  }

  async getEffectiveOnDates(dates: string[]): Promise<Record<string, WeeklyGoal | undefined>> {
    if (dates.length === 0) {
      return {}
    }

    const latestDate = dates.reduce((latest, date) => date > latest ? date : latest)
    const goals = await this.database.weeklyGoals.where('effectiveFrom').belowOrEqual(latestDate).toArray()

    return dates.reduce<Record<string, WeeklyGoal | undefined>>((goalsByDate, date) => {
      goalsByDate[date] = getMostRecentGoal(goals.filter((goal) => goal.effectiveFrom <= date))
      return goalsByDate
    }, {})
  }

  async getLatest(): Promise<WeeklyGoal | undefined> {
    return getMostRecentGoal(await this.database.weeklyGoals.toArray())
  }
}

function getMostRecentGoal(goals: WeeklyGoal[]): WeeklyGoal | undefined {
  return goals.reduce<WeeklyGoal | undefined>((latest, goal) => {
    if (latest === undefined || compareGoals(latest, goal) < 0) {
      return goal
    }

    return latest
  }, undefined)
}

/** Resolves legacy duplicate effective dates deterministically. */
function compareGoals(left: WeeklyGoal, right: WeeklyGoal): number {
  return left.effectiveFrom.localeCompare(right.effectiveFrom)
    || left.createdAt.localeCompare(right.createdAt)
    || left.id.localeCompare(right.id)
}
