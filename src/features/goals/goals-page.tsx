import { useEffect, useRef, useState, type FormEvent } from 'react'
import { useLocation } from 'react-router-dom'

import { DuplicateGoalEffectiveFromError } from '@/application/goals/goal-service'
import { applicationServices } from '@/app/providers/application-services'
import type { DailyMacroGoal, WeeklyGoal, WeeklyGoalDay } from '@/domain/goals/weekly-goal'
import { weeklyGoalDays } from '@/domain/goals/weekly-goal'
import { fromLocalDateKey, isLocalDateKey, toLocalDateKey } from '@/shared/utils/local-date-key'

type GoalMacroField = keyof DailyMacroGoal
type GoalFormDay = Record<GoalMacroField, string>
type GoalFormValues = Record<WeeklyGoalDay, GoalFormDay>

const dayLabels: Record<WeeklyGoalDay, string> = {
  monday: 'Понедельник',
  tuesday: 'Вторник',
  wednesday: 'Среда',
  thursday: 'Четверг',
  friday: 'Пятница',
  saturday: 'Суббота',
  sunday: 'Воскресенье',
}

const macroFields: Array<{ key: GoalMacroField; label: string; unit: string }> = [
  { key: 'calories', label: 'Калории', unit: 'ккал' },
  { key: 'protein', label: 'Белки', unit: 'г' },
  { key: 'fat', label: 'Жиры', unit: 'г' },
  { key: 'carbs', label: 'Углеводы', unit: 'г' },
]

export function GoalsPage() {
  const location = useLocation()
  const [effectiveFrom, setEffectiveFrom] = useState(toLocalDateKey)
  const [goals, setGoals] = useState<GoalFormValues>(createEmptyGoalForm)
  const [applySourceDay, setApplySourceDay] = useState<WeeklyGoalDay>('monday')
  const [editingDay, setEditingDay] = useState<WeeklyGoalDay | undefined>()
  const [latestGoal, setLatestGoal] = useState<WeeklyGoal | undefined>()
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | undefined>()
  const [success, setSuccess] = useState<string | undefined>()
  const isSubmittingRef = useRef(false)

  useEffect(() => {
    let isMounted = true

    async function loadGoals(): Promise<void> {
      setIsLoading(true)
      setError(undefined)
      const requestedDate = getRequestedEffectiveFrom(location.state)

      try {
        const latest = await applicationServices.goals.getLatestWeeklyGoal()

        if (!isMounted) {
          return
        }

        setLatestGoal(latest)
        setGoals(latest === undefined ? createEmptyGoalForm() : toGoalForm(latest))
        setEffectiveFrom(requestedDate ?? toLocalDateKey())
        setEditingDay(latest === undefined ? 'monday' : undefined)
      } catch (loadError) {
        console.error('Failed to load weekly goals.', loadError)

        if (isMounted) {
          setError('Не удалось загрузить цели. Попробуйте ещё раз.')
        }
      } finally {
        if (isMounted) {
          setIsLoading(false)
        }
      }
    }

    void loadGoals()

    return () => {
      isMounted = false
    }
  }, [location.state])

  function updateGoal(day: WeeklyGoalDay, field: GoalMacroField, value: string): void {
    setGoals((current) => ({
      ...current,
      [day]: { ...current[day], [field]: value },
    }))
    setSuccess(undefined)
  }

  function applyToAllDays(): void {
    const sourceGoal = goals[applySourceDay]
    setGoals(createGoalFormFromSingleDay(sourceGoal))
    setSuccess(undefined)
  }

  async function saveGoals(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault()

    if (isSubmittingRef.current) {
      return
    }

    setError(undefined)
    setSuccess(undefined)

    let parsedGoals: Record<WeeklyGoalDay, DailyMacroGoal>

    try {
      parsedGoals = parseGoalForm(goals)
    } catch {
      setError('Введите неотрицательные числа для всех целей.')
      return
    }

    isSubmittingRef.current = true
    setIsSaving(true)

    try {
      const savedGoal = await applicationServices.goals.saveWeeklyGoal({ effectiveFrom, goals: parsedGoals })
      setLatestGoal(savedGoal)
      setSuccess(`Цели сохранены. Действуют с ${formatDate(savedGoal.effectiveFrom)}.`)
    } catch (saveError) {
      console.error('Failed to save weekly goals.', saveError)
      setError(saveError instanceof DuplicateGoalEffectiveFromError
        ? 'Для этой даты цели уже существуют. Выберите другую дату начала действия.'
        : 'Не удалось сохранить цели. Проверьте дату и значения.')
    } finally {
      isSubmittingRef.current = false
      setIsSaving(false)
    }
  }

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  return (
    <section className="goals-page" aria-labelledby="goals-title">
      <div className="page-heading">
        <div>
          <h1 id="goals-title">Цели</h1>
          <p>{latestGoal === undefined ? 'Задайте цели КБЖУ для каждого дня недели.' : 'Сохранение создаёт новую версию целей и сохраняет историю.'}</p>
        </div>
      </div>

      <form className="goals-form" noValidate onSubmit={(event) => void saveGoals(event)}>
        <section className="goals-effective-date" aria-labelledby="goals-effective-date-title">
          <div>
            <h2 id="goals-effective-date-title">Дата начала действия</h2>
            <p>{latestGoal === undefined ? 'По умолчанию — сегодня.' : `Основа: цели с ${formatDate(latestGoal.effectiveFrom)}.`}</p>
          </div>
          <label className="form-field" htmlFor="goal-effective-from">
            <span className="sr-only">Дата начала действия</span>
            <input id="goal-effective-from" type="date" value={effectiveFrom} onChange={(event) => setEffectiveFrom(event.target.value)} />
          </label>
        </section>

        <section className="goals-apply" aria-labelledby="goals-apply-title">
          <div>
            <h2 id="goals-apply-title">Применить ко всем дням</h2>
            <p>Скопирует значения выбранного дня. Затем любой день можно изменить отдельно.</p>
          </div>
          <div className="goals-apply__actions">
            <select aria-label="Источник значений для всех дней" value={applySourceDay} onChange={(event) => setApplySourceDay(event.target.value as WeeklyGoalDay)}>
              {weeklyGoalDays.map((day) => <option key={day} value={day}>{dayLabels[day]}</option>)}
            </select>
            <button className="button button--secondary" type="button" onClick={applyToAllDays}>Применить</button>
          </div>
        </section>

        <ol className="goals-day-list">
          {weeklyGoalDays.map((day) => (
            <li key={day} className={editingDay === day ? 'goals-day-card goals-day-card--editing' : 'goals-day-card'}>
              <div className="goals-day-card__header">
                <div>
                  <h2>{dayLabels[day]}</h2>
                  {editingDay === day ? <p>Укажите КБЖУ на этот день.</p> : <p>{formatGoalSummary(goals[day])}</p>}
                </div>
                <button className="button button--secondary button--small" type="button" onClick={() => setEditingDay(editingDay === day ? undefined : day)}>
                  {editingDay === day ? 'Готово' : 'Изменить'}
                </button>
              </div>
              {editingDay !== day ? null : (
                <div className="macro-input-grid goals-day-card__fields">
                  {macroFields.map((field) => (
                    <GoalNumberField
                      key={field.key}
                      day={day}
                      field={field.key}
                      label={field.label}
                      unit={field.unit}
                      value={goals[day][field.key]}
                      onChange={updateGoal}
                    />
                  ))}
                </div>
              )}
            </li>
          ))}
        </ol>

        {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
        {success === undefined ? null : <p className="goals-success" role="status">{success}</p>}
        <div className="form-actions goals-form__actions">
          <button className="button button--primary" disabled={isSaving} type="submit">{isSaving ? 'Сохранение…' : 'Сохранить цели'}</button>
        </div>
      </form>
    </section>
  )
}

interface GoalNumberFieldProps {
  day: WeeklyGoalDay
  field: GoalMacroField
  label: string
  unit: string
  value: string
  onChange: (day: WeeklyGoalDay, field: GoalMacroField, value: string) => void
}

function GoalNumberField({ day, field, label, unit, value, onChange }: GoalNumberFieldProps) {
  const id = `goal-${day}-${field}`

  return (
    <div className="form-field">
      <label htmlFor={id}>{label}</label>
      <div className="input-with-unit">
        <input id={id} type="number" inputMode="decimal" min="0" step="any" value={value} onChange={(event) => onChange(day, field, event.target.value)} />
        <span>{unit}</span>
      </div>
    </div>
  )
}

function createEmptyGoalForm(): GoalFormValues {
  return createGoalFormFromSingleDay({ calories: '0', protein: '0', fat: '0', carbs: '0' })
}

function createGoalFormFromSingleDay(goal: GoalFormDay): GoalFormValues {
  return weeklyGoalDays.reduce<GoalFormValues>((allGoals, day) => {
    allGoals[day] = { ...goal }
    return allGoals
  }, {} as GoalFormValues)
}

function toGoalForm(goal: WeeklyGoal): GoalFormValues {
  return weeklyGoalDays.reduce<GoalFormValues>((form, day) => {
    form[day] = toGoalFormDay(goal[day])
    return form
  }, {} as GoalFormValues)
}

function toGoalFormDay(goal: DailyMacroGoal): GoalFormDay {
  return {
    calories: String(goal.calories),
    protein: String(goal.protein),
    fat: String(goal.fat),
    carbs: String(goal.carbs),
  }
}

function parseGoalForm(form: GoalFormValues): Record<WeeklyGoalDay, DailyMacroGoal> {
  return weeklyGoalDays.reduce<Record<WeeklyGoalDay, DailyMacroGoal>>((goals, day) => {
    const dayGoal = form[day]
    goals[day] = {
      calories: parseGoalValue(dayGoal.calories),
      protein: parseGoalValue(dayGoal.protein),
      fat: parseGoalValue(dayGoal.fat),
      carbs: parseGoalValue(dayGoal.carbs),
    }
    return goals
  }, {} as Record<WeeklyGoalDay, DailyMacroGoal>)
}

function parseGoalValue(value: string): number {
  const parsedValue = Number(value)

  if (value.trim() === '' || !Number.isFinite(parsedValue) || parsedValue < 0) {
    throw new Error('Goal value is invalid.')
  }

  return parsedValue
}

function formatGoalSummary(goal: GoalFormDay): string {
  return `${formatGoalValue(goal.calories)} ккал · Б ${formatGoalValue(goal.protein)} · Ж ${formatGoalValue(goal.fat)} · У ${formatGoalValue(goal.carbs)}`
}

function formatGoalValue(value: string): string {
  const number = Number(value)

  return Number.isFinite(number) && number >= 0 ? new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1 }).format(number) : '—'
}

function getRequestedEffectiveFrom(state: unknown): string | undefined {
  if (typeof state !== 'object' || state === null || !('effectiveFrom' in state)) {
    return undefined
  }

  const effectiveFrom = (state as { effectiveFrom?: unknown }).effectiveFrom

  return typeof effectiveFrom === 'string' && isLocalDateKey(effectiveFrom) ? effectiveFrom : undefined
}

function formatDate(dateKey: string): string {
  return new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' }).format(fromLocalDateKey(dateKey))
}
