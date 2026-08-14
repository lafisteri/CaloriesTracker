import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'

import type { WeekStats } from '@/application/statistics/statistics-service'
import { applicationServices } from '@/app/providers/application-services'
import { DiaryDateNavigation } from '@/features/diary/diary-date-navigation'
import { shiftLocalDateKey, toLocalDateKey } from '@/shared/utils/local-date-key'

import { WeeklyCaloriesCard, WeeklyMacroCard } from './dashboard-cards'

export function TodayPage() {
  const [date, setDate] = useState(toLocalDateKey)
  const [weekStats, setWeekStats] = useState<WeekStats | undefined>()
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const loadRequestId = useRef(0)

  const loadDashboard = useCallback(async (dateKey: string) => {
    const requestId = ++loadRequestId.current
    setIsLoading(true)
    setError(undefined)

    try {
      const loadedWeekStats = await applicationServices.statistics.getWeekStats(dateKey)

      if (requestId === loadRequestId.current) {
        setWeekStats(loadedWeekStats)
      }
    } catch (loadError) {
      console.error('Failed to load dashboard statistics.', loadError)

      if (requestId === loadRequestId.current) {
        setError('Не удалось загрузить сводку. Попробуйте ещё раз.')
      }
    } finally {
      if (requestId === loadRequestId.current) {
        setIsLoading(false)
      }
    }
  }, [])

  useEffect(() => {
    void loadDashboard(date)
  }, [date, loadDashboard])

  return (
    <section className="dashboard-page" aria-labelledby="dashboard-title">
      <header className="dashboard-page__header">
        <h1 id="dashboard-title">Статистика</h1>
        <Link className="dashboard-page__goals-link" to="/goals" state={{ effectiveFrom: date }}>Настроить цели</Link>
      </header>
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
          <button className="button button--secondary" type="button" onClick={() => void loadDashboard(date)}>Повторить</button>
        </div>
      )}
      {weekStats === undefined || isLoading || error !== undefined ? null : (
        <>
          <WeeklyCaloriesCard stats={weekStats} />
          <WeeklyMacroCard stats={weekStats} />
        </>
      )}
    </section>
  )
}
