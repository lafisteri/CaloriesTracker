import { Link } from 'react-router-dom'

import type { DayStats, WeekStats } from '@/application/statistics/statistics-service'

import {
  formatCalorieGoalStatus,
  formatDashboardNumber,
  formatMacroDistribution,
  formatWeeklyBalance,
  getCalorieBarHeight,
  getCalorieBarLabel,
  getCalorieBarState,
  weekDayShortLabels,
} from './dashboard-formatters'

type MacroKey = 'protein' | 'fat' | 'carbs'

const macroMetrics: Array<{ key: MacroKey; label: string; className: string }> = [
  { key: 'protein', label: 'Белки', className: 'dashboard-macro__fill--protein' },
  { key: 'fat', label: 'Жиры', className: 'dashboard-macro__fill--fat' },
  { key: 'carbs', label: 'Углеводы', className: 'dashboard-macro__fill--carbs' },
]

export function CaloriesCard({ stats }: { stats: DayStats }) {
  const target = stats.goal?.calories
  const hasGoal = target !== undefined && target > 0

  return (
    <section className="dashboard-card dashboard-calories" aria-labelledby="dashboard-calories-title">
      <h2 id="dashboard-calories-title">Калории</h2>
      <p className="dashboard-calories__value">
        {formatDashboardNumber(stats.calories)}{hasGoal ? ` / ${formatDashboardNumber(target)}` : ''} <span>ккал</span>
      </p>
      <p className="dashboard-calories__status">{formatCalorieGoalStatus(stats.calories, target)}</p>
      {stats.goal === undefined ? <Link className="dashboard-card__link" to="/goals" state={{ effectiveFrom: stats.date }}>Задать цели</Link> : null}
    </section>
  )
}

export function DailyMacroCard({ stats }: { stats: DayStats }) {
  return (
    <section className="dashboard-card dashboard-macros" aria-labelledby="dashboard-macros-title">
      <div className="dashboard-card__heading">
        <h2 id="dashboard-macros-title">Макронутриенты</h2>
        <span>за день</span>
      </div>
      <dl>
        {macroMetrics.map((metric) => {
          const actual = stats[metric.key]
          const target = stats.goal?.[metric.key]
          const hasGoal = target !== undefined && target > 0
          const progress = hasGoal ? Math.min(actual / target * 100, 100) : 0

          return (
            <div key={metric.key} className="dashboard-macro">
              <div className="dashboard-macro__values">
                <dt>{metric.label}</dt>
                <dd>{formatDashboardNumber(actual)}{hasGoal ? ` / ${formatDashboardNumber(target)}` : ''} г</dd>
              </div>
              {hasGoal ? (
                <div className="dashboard-macro__track" aria-label={`${metric.label}: ${formatDashboardNumber(actual)} из ${formatDashboardNumber(target)} г`}>
                  <span className={`dashboard-macro__fill ${metric.className}${actual > target ? ' dashboard-macro__fill--over' : ''}`} style={{ width: `${progress}%` }} />
                </div>
              ) : <p className="dashboard-macro__no-goal">Цель не задана</p>}
            </div>
          )
        })}
      </dl>
    </section>
  )
}

export function WeeklyCaloriesCard({ stats }: { stats: WeekStats }) {
  return (
    <section className="dashboard-card weekly-calories" aria-labelledby="weekly-calories-title">
      <div className="dashboard-card__heading">
        <h2 id="weekly-calories-title">Калории за неделю</h2>
        <span>100% = цель дня</span>
      </div>
      <div className="weekly-calories__chart" role="list" aria-label="Калории по дням недели">
        {stats.days.map((day, index) => {
          const state = getCalorieBarState(day)
          const target = day.goal?.calories
          const status = state === 'no-goal'
            ? `${formatDashboardNumber(day.calories)} ккал`
            : state === 'empty' ? 'Нет записей' : `${formatDashboardNumber(day.calories / target! * 100)}%`

          return (
            <div key={day.date} className="weekly-calories__day" role="listitem" aria-label={`${weekDayShortLabels[index]}: ${getCalorieBarLabel(day)} `}>
              <div className="weekly-calories__track" aria-hidden="true">
                {target !== undefined && target > 0 ? <span className="weekly-calories__goal-line" /> : null}
                <span className={`weekly-calories__bar weekly-calories__bar--${state}`} style={{ height: `${getCalorieBarHeight(day)}%` }} />
              </div>
              <strong>{weekDayShortLabels[index]}</strong>
              <span>{status}</span>
            </div>
          )
        })}
      </div>
      {stats.calorieBalance === undefined ? null : <p className="weekly-calories__balance">{formatWeeklyBalance(stats.calorieBalance)}</p>}
    </section>
  )
}

export function WeeklyMacroCard({ stats }: { stats: WeekStats }) {
  return (
    <section className="dashboard-card weekly-macros" aria-labelledby="weekly-macros-title">
      <div className="dashboard-card__heading">
        <h2 id="weekly-macros-title">БЖУ за неделю</h2>
        <span>доля энергии</span>
      </div>
      <div className="macro-legend" aria-label="Обозначения графика">
        {macroMetrics.map((metric) => <span key={metric.key}><i className={metric.className} />{metric.label}</span>)}
      </div>
      <div className="weekly-macros__chart" role="list" aria-label="Распределение БЖУ по дням недели">
        {stats.days.map((day, index) => (
          <div key={day.date} className="weekly-macros__day" role="listitem" aria-label={`${weekDayShortLabels[index]}: ${day.macroDistribution.totalEnergy === 0 ? 'нет данных' : formatMacroDistribution(day.macroDistribution)}`}>
            <div className="weekly-macros__bar" aria-hidden="true">
              {day.macroDistribution.totalEnergy === 0 ? null : macroMetrics.map((metric) => (
                <span key={metric.key} className={`weekly-macros__segment ${metric.className}`} style={{ height: `${day.macroDistribution[metric.key]}%` }} />
              ))}
            </div>
            <span>{weekDayShortLabels[index]}</span>
          </div>
        ))}
      </div>
      {stats.macroDistribution.totalEnergy === 0 ? <p className="weekly-macros__empty">За эту неделю пока нет БЖУ для распределения.</p> : <p className="weekly-macros__average">Среднее: {formatMacroDistribution(stats.macroDistribution)}</p>}
    </section>
  )
}
