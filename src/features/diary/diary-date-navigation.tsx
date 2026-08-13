import { toLocalDateKey } from '@/shared/utils/local-date-key'

import { formatDiaryDate } from './diary-formatters'

interface DiaryDateNavigationProps {
  date: string
  onChange: (date: string) => void
  onPrevious: () => void
  onNext: () => void
}

export function DiaryDateNavigation({ date, onChange, onPrevious, onNext }: DiaryDateNavigationProps) {
  const isToday = date === toLocalDateKey()

  return (
    <div className="diary-date-navigation">
      <button className="date-navigation__button" type="button" aria-label="Предыдущий день" onClick={onPrevious}>‹</button>
      <label className="diary-date-navigation__label">
        <span>{formatDiaryDate(date)}</span>
        <input type="date" value={date} onChange={(event) => onChange(event.target.value)} aria-label="Выбрать дату" />
      </label>
      <button className="date-navigation__button" type="button" aria-label="Следующий день" onClick={onNext}>›</button>
      {isToday ? null : <button className="today-button" type="button" onClick={() => onChange(toLocalDateKey())}>Сегодня</button>}
    </div>
  )
}
