import { Link } from 'react-router-dom'

import type { DailyMacroGoal } from '@/domain/goals/weekly-goal'
import type { Nutrition } from '@/domain/nutrition/nutrition'

import { formatDiaryNumber } from './diary-formatters'

interface DailyGoalSummaryProps {
  date: string
  totals: Nutrition
  goal: DailyMacroGoal | undefined
}

export function DailyGoalSummary({ date, totals, goal }: DailyGoalSummaryProps) {
  const calorieGoal = goal?.calories
  const hasCalorieGoal = calorieGoal !== undefined && calorieGoal > 0
  const calorieOverage = hasCalorieGoal ? totals.calories - calorieGoal : 0

  return (
    <section className="diary-totals" aria-labelledby="diary-totals-title">
      <div className="diary-totals__heading">
        <h2 id="diary-totals-title">За день</h2>
        {goal === undefined ? <Link className="diary-goal-link" to="/goals" state={{ effectiveFrom: date }}>Задать цели</Link> : null}
      </div>
      <p className="diary-totals__calories">
        <strong>{formatDiaryNumber(totals.calories)}{hasCalorieGoal ? ` / ${formatDiaryNumber(calorieGoal)}` : ''} ккал</strong>
        {calorieOverage > 0 ? <span> · +{formatDiaryNumber(calorieOverage)}</span> : null}
      </p>
      <p className="diary-totals__macros">Б {formatDiaryNumber(totals.protein)} · Ж {formatDiaryNumber(totals.fat)} · У {formatDiaryNumber(totals.carbs)}</p>
    </section>
  )
}
