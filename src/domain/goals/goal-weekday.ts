import type { WeeklyGoalDay } from '@/domain/goals/weekly-goal'
import { fromLocalDateKey } from '@/shared/utils/local-date-key'

const goalDayByJavaScriptDay: Record<number, WeeklyGoalDay> = {
  0: 'sunday',
  1: 'monday',
  2: 'tuesday',
  3: 'wednesday',
  4: 'thursday',
  5: 'friday',
  6: 'saturday',
}

/** Maps a local YYYY-MM-DD date key to the corresponding weekly goal day. */
export function getWeeklyGoalDayForDate(dateKey: string): WeeklyGoalDay {
  return goalDayByJavaScriptDay[fromLocalDateKey(dateKey).getDay()]
}
