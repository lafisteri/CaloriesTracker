import { useCallback, useEffect, useRef, useState } from 'react'
import { useLocation } from 'react-router-dom'

import type { DiaryDay } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'
import type { MealType } from '@/domain/diary/diary-entry'
import { toLocalDateKey, shiftLocalDateKey } from '@/shared/utils/local-date-key'

import { DiaryDateNavigation } from './diary-date-navigation'
import { formatDiaryNumber, mealTypes } from './diary-formatters'
import { FoodPickerSheet } from './food-picker-sheet'
import { MealSection } from './meal-section'

export function DiaryPage() {
  const location = useLocation()
  const [date, setDate] = useState(toLocalDateKey)
  const [day, setDay] = useState<DiaryDay | undefined>()
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const [pickerMealType, setPickerMealType] = useState<MealType | undefined>()
  const loadRequestId = useRef(0)

  const loadDay = useCallback(async (dateKey: string) => {
    const requestId = ++loadRequestId.current
    setIsLoading(true)
    setError(undefined)

    try {
      const loadedDay = await applicationServices.diary.getDay(dateKey)

      if (requestId === loadRequestId.current) {
        setDay(loadedDay)
      }
    } catch (loadError) {
      console.error('Failed to load diary day.', loadError)

      if (requestId === loadRequestId.current) {
        setError('Не удалось загрузить дневник. Попробуйте ещё раз.')
      }
    } finally {
      if (requestId === loadRequestId.current) {
        setIsLoading(false)
      }
    }
  }, [])

  useEffect(() => {
    void loadDay(date)
  }, [date, loadDay])

  useEffect(() => {
    const state = location.state as { date?: string } | null

    if (state?.date !== undefined) {
      setDate(state.date)
    }
  }, [location.state])

  function closePicker(): void {
    setPickerMealType(undefined)
  }

  function handleAdded(): void {
    closePicker()
    void loadDay(date)
  }

  return (
    <section className="diary-page" aria-labelledby="diary-title">
      <h1 id="diary-title" className="sr-only">Дневник</h1>
      <DiaryDateNavigation
        date={date}
        onChange={setDate}
        onPrevious={() => setDate((currentDate) => shiftLocalDateKey(currentDate, -1))}
        onNext={() => setDate((currentDate) => shiftLocalDateKey(currentDate, 1))}
      />

      {isLoading ? <p className="status-message">Загрузка…</p> : null}
      {error === undefined ? null : (
        <div className="status-message status-message--error" role="alert">
          <p>{error}</p>
          <button className="button button--secondary" type="button" onClick={() => void loadDay(date)}>Повторить</button>
        </div>
      )}
      {day === undefined || isLoading || error !== undefined ? null : (
        <>
          <section className="diary-totals" aria-labelledby="diary-totals-title">
            <h2 id="diary-totals-title">За день</h2>
            <dl>
              <div><dt>Калории</dt><dd>{formatDiaryNumber(day.totals.calories)}</dd></div>
              <div><dt>Белки</dt><dd>{formatDiaryNumber(day.totals.protein)} г</dd></div>
              <div><dt>Жиры</dt><dd>{formatDiaryNumber(day.totals.fat)} г</dd></div>
              <div><dt>Углеводы</dt><dd>{formatDiaryNumber(day.totals.carbs)} г</dd></div>
            </dl>
          </section>

          {day.entries.length === 0 ? <p className="diary-empty">{date === toLocalDateKey() ? 'Сегодня пока ничего не добавлено' : 'На этот день пока ничего не добавлено'}</p> : null}
          <div className="meal-sections">
            {mealTypes.map((mealType) => (
              <MealSection key={mealType} mealType={mealType} meal={day.meals[mealType]} onAdd={setPickerMealType} />
            ))}
          </div>
        </>
      )}

      {pickerMealType === undefined ? null : <FoodPickerSheet date={date} mealType={pickerMealType} onClose={closePicker} onAdded={handleAdded} />}
    </section>
  )
}
