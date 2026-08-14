import { Link } from 'react-router-dom'

import type { DailyMacroGoal } from '@/domain/goals/weekly-goal'
import type { Nutrition } from '@/domain/nutrition/nutrition'

import { formatDiaryNumber } from './diary-formatters'

interface DailyGoalSummaryProps {
  date: string
  totals: Nutrition
  goal: DailyMacroGoal | undefined
}

const goalMetrics: Array<{ key: keyof DailyMacroGoal; label: string; unit: string }> = [
  { key: 'calories', label: 'Калории', unit: 'ккал' },
  { key: 'protein', label: 'Белки', unit: 'г' },
  { key: 'fat', label: 'Жиры', unit: 'г' },
  { key: 'carbs', label: 'Углеводы', unit: 'г' },
]

export function DailyGoalSummary({ date, totals, goal }: DailyGoalSummaryProps) {
  return (
    <section className="diary-totals" aria-labelledby="diary-totals-title">
      <h2 id="diary-totals-title">За день</h2>
      <dl>
        {goalMetrics.map((metric) => {
          const actual = totals[metric.key]
          const target = goal?.[metric.key]

          return (
            <div key={metric.key}>
              <dt>{metric.label}</dt>
              <dd>{formatMetricValue(actual, target, metric.unit)}</dd>
              {target === undefined ? null : <small>{formatGoalDifference(actual, target, metric.unit)}</small>}
            </div>
          )
        })}
      </dl>
      {goal === undefined ? <Link className="diary-goal-link" to="/goals" state={{ effectiveFrom: date }}>Задать цели</Link> : null}
    </section>
  )
}

function formatMetricValue(actual: number, target: number | undefined, unit: string): string {
  if (target === undefined || target === 0) {
    return `${formatDiaryNumber(actual)} ${unit}`
  }

  return `${formatDiaryNumber(actual)} / ${formatDiaryNumber(target)} ${unit}`
}

function formatGoalDifference(actual: number, target: number, unit: string): string {
  if (target === 0) {
    return 'Цель не задана'
  }

  const difference = target - actual

  return difference >= 0
    ? `Осталось ${formatDiaryNumber(difference)} ${unit}`
    : `+${formatDiaryNumber(Math.abs(difference))} ${unit} к цели`
}
