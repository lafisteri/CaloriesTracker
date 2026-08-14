import type { WeekStats } from '@/application/statistics/statistics-service'

import {
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
      {stats.macroDistribution.totalEnergy === 0 ? null : <p className="weekly-macros__average">Среднее: {formatMacroDistribution(stats.macroDistribution)}</p>}
    </section>
  )
}
