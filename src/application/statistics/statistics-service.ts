import type { DiaryService } from '@/application/diary/diary-service'
import type { GoalService } from '@/application/goals/goal-service'
import type { DailyMacroGoal } from '@/domain/goals/weekly-goal'
import type { Nutrition } from '@/domain/nutrition/nutrition'
import { isLocalDateKey, toLocalDateKey } from '@/shared/utils/local-date-key'
import { getWeekRange } from '@/shared/utils/week-range'

export interface DayStats extends Nutrition {
  date: string
  goal?: DailyMacroGoal
  macroDistribution: MacroDistribution
}

export interface MacroDistribution {
  protein: number
  fat: number
  carbs: number
  totalEnergy: number
}

export interface WeeklyCalorieBalance {
  actualCalories: number
  goalCalories: number
  difference: number
  includedDays: number
}

export interface WeekStats {
  days: DayStats[]
  macroDistribution: MacroDistribution
  calorieBalance?: WeeklyCalorieBalance
}

/** Aggregates immutable diary snapshots and date-effective goals for Dashboard. */
export class StatisticsService {
  constructor(
    private readonly diaryService: DiaryService,
    private readonly goalService: GoalService,
  ) {}

  async getDailyStats(date: string): Promise<DayStats> {
    assertDateKey(date)
    const [totals, goal] = await Promise.all([
      this.diaryService.getTotalsForDate(date),
      this.goalService.getGoalForDate(date),
    ])

    return { date, ...totals, goal, macroDistribution: calculateMacroDistribution(totals) }
  }

  async getWeekStats(date: string): Promise<WeekStats> {
    assertDateKey(date)
    const dates = getWeekRange(date)
    const [totalsByDate, goalsByDate] = await Promise.all([
      this.diaryService.getTotalsForDates(dates),
      this.goalService.getGoalsForDates(dates),
    ])
    const days = dates.map((day) => ({
      date: day,
      ...totalsByDate[day],
      goal: goalsByDate[day],
      macroDistribution: calculateMacroDistribution(totalsByDate[day]),
    }))

    return {
      days,
      macroDistribution: calculateMacroDistribution(sumNutrition(days)),
      calorieBalance: calculateWeeklyCalorieBalance(days),
    }
  }

  async getWeeklyCalorieBalance(date: string): Promise<WeeklyCalorieBalance | undefined> {
    return (await this.getWeekStats(date)).calorieBalance
  }

  async getDailyMacroDistribution(date: string): Promise<MacroDistribution> {
    return calculateMacroDistribution(await this.getDailyStats(date))
  }

  async getWeeklyMacroDistribution(date: string): Promise<MacroDistribution> {
    return (await this.getWeekStats(date)).macroDistribution
  }
}

function calculateWeeklyCalorieBalance(days: DayStats[]): WeeklyCalorieBalance | undefined {
  const includedDays = getBalanceDays(days)
  const daysWithGoals = includedDays.filter((day) => day.goal !== undefined && day.goal.calories > 0)

  if (daysWithGoals.length === 0) {
    return undefined
  }

  const actualCalories = daysWithGoals.reduce((total, day) => total + day.calories, 0)
  const goalCalories = daysWithGoals.reduce((total, day) => total + day.goal!.calories, 0)

  return {
    actualCalories,
    goalCalories,
    difference: actualCalories - goalCalories,
    includedDays: daysWithGoals.length,
  }
}

function getBalanceDays(days: DayStats[]): DayStats[] {
  const today = toLocalDateKey()
  const firstDay = days[0]?.date
  const lastDay = days.at(-1)?.date

  if (firstDay === undefined || lastDay === undefined || firstDay > today) {
    return []
  }

  return lastDay >= today ? days.filter((day) => day.date <= today) : days
}

function calculateMacroDistribution(nutrition: Nutrition): MacroDistribution {
  const proteinEnergy = nutrition.protein * 4
  const fatEnergy = nutrition.fat * 9
  const carbsEnergy = nutrition.carbs * 4
  const totalEnergy = proteinEnergy + fatEnergy + carbsEnergy

  if (totalEnergy === 0) {
    return { protein: 0, fat: 0, carbs: 0, totalEnergy: 0 }
  }

  return {
    protein: proteinEnergy / totalEnergy * 100,
    fat: fatEnergy / totalEnergy * 100,
    carbs: carbsEnergy / totalEnergy * 100,
    totalEnergy,
  }
}

function sumNutrition(days: DayStats[]): Nutrition {
  return days.reduce<Nutrition>((total, day) => ({
    calories: total.calories + day.calories,
    protein: total.protein + day.protein,
    fat: total.fat + day.fat,
    carbs: total.carbs + day.carbs,
  }), { calories: 0, protein: 0, fat: 0, carbs: 0 })
}

function assertDateKey(date: string): void {
  if (!isLocalDateKey(date)) {
    throw new Error('Statistics date must be a valid local date key.')
  }
}
