import { getWeeklyGoalDayForDate } from '@/domain/goals/goal-weekday'
import type { DailyMacroGoal, WeeklyGoal, WeeklyGoalsByDay } from '@/domain/goals/weekly-goal'
import { weeklyGoalDays } from '@/domain/goals/weekly-goal'
import type { GoalRepository } from '@/domain/repositories/goal-repository'
import { createUuid } from '@/shared/utils/create-uuid'
import { isLocalDateKey } from '@/shared/utils/local-date-key'

export interface WeeklyGoalDraft {
  effectiveFrom: string
  goals: WeeklyGoalsByDay
}

/** Application service for immutable, date-effective nutrition goals. */
export class GoalService {
  constructor(private readonly goalRepository: GoalRepository) {}

  async getGoalForDate(date: string): Promise<DailyMacroGoal | undefined> {
    const weeklyGoal = await this.getWeeklyGoalForDate(date)

    return weeklyGoal === undefined ? undefined : cloneDailyGoal(weeklyGoal[getWeeklyGoalDayForDate(date)])
  }

  async getWeeklyGoalForDate(date: string): Promise<WeeklyGoal | undefined> {
    assertDateKey(date)

    return this.goalRepository.getEffectiveOn(date)
  }

  async getGoalsForDates(dates: string[]): Promise<Record<string, DailyMacroGoal | undefined>> {
    dates.forEach(assertDateKey)
    const weeklyGoals = await this.goalRepository.getEffectiveOnDates(dates)

    return dates.reduce<Record<string, DailyMacroGoal | undefined>>((goals, date) => {
      const weeklyGoal = weeklyGoals[date]
      goals[date] = weeklyGoal === undefined ? undefined : cloneDailyGoal(weeklyGoal[getWeeklyGoalDayForDate(date)])
      return goals
    }, {})
  }

  getLatestWeeklyGoal(): Promise<WeeklyGoal | undefined> {
    return this.goalRepository.getLatest()
  }

  async saveWeeklyGoal(draft: WeeklyGoalDraft): Promise<WeeklyGoal> {
    assertDateKey(draft.effectiveFrom)
    assertGoalValues(draft.goals)
    const createdAt = new Date().toISOString()
    const goal: WeeklyGoal = {
      id: createUuid(),
      effectiveFrom: draft.effectiveFrom,
      monday: cloneDailyGoal(draft.goals.monday),
      tuesday: cloneDailyGoal(draft.goals.tuesday),
      wednesday: cloneDailyGoal(draft.goals.wednesday),
      thursday: cloneDailyGoal(draft.goals.thursday),
      friday: cloneDailyGoal(draft.goals.friday),
      saturday: cloneDailyGoal(draft.goals.saturday),
      sunday: cloneDailyGoal(draft.goals.sunday),
      createdAt,
    }

    const wasCreated = await this.goalRepository.create(goal)

    if (!wasCreated) {
      throw new DuplicateGoalEffectiveFromError()
    }

    return goal
  }
}

export class InvalidWeeklyGoalError extends Error {
  constructor() {
    super('Weekly goal must contain finite non-negative nutrition values.')
    this.name = 'InvalidWeeklyGoalError'
  }
}

export class DuplicateGoalEffectiveFromError extends Error {
  constructor() {
    super('A weekly goal already starts on this effective date.')
    this.name = 'DuplicateGoalEffectiveFromError'
  }
}

function assertDateKey(date: string): void {
  if (!isLocalDateKey(date)) {
    throw new InvalidWeeklyGoalError()
  }
}

function assertGoalValues(goals: WeeklyGoalsByDay): void {
  const values = weeklyGoalDays.flatMap((day) => Object.values(goals[day]))

  if (values.some((value) => !Number.isFinite(value) || value < 0)) {
    throw new InvalidWeeklyGoalError()
  }
}

function cloneDailyGoal(goal: DailyMacroGoal): DailyMacroGoal {
  return {
    calories: goal.calories,
    protein: goal.protein,
    fat: goal.fat,
    carbs: goal.carbs,
  }
}
