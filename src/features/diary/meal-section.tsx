import { Link } from 'react-router-dom'

import type { DiaryMeal } from '@/application/diary/diary-service'
import type { MealType } from '@/domain/diary/diary-entry'

import { formatDiaryNumber, getMealTypeLabel } from './diary-formatters'

interface MealSectionProps {
  mealType: MealType
  meal: DiaryMeal
  onAdd: () => void
}

export function MealSection({ mealType, meal, onAdd }: MealSectionProps) {
  const isEmpty = meal.entries.length === 0

  return (
    <section className={isEmpty ? 'meal-section meal-section--empty' : 'meal-section'} aria-labelledby={`meal-${mealType}`}>
      <div className="meal-section__header">
        <div>
          <h2 id={`meal-${mealType}`}>{getMealTypeLabel(mealType)}</h2>
          <p>{formatDiaryNumber(meal.totals.calories)} ккал</p>
        </div>
        <button className="button button--secondary button--small" type="button" onClick={onAdd}>+ Добавить</button>
      </div>
      {isEmpty ? null : (
        <ul className="diary-entry-list">
          {meal.entries.map((entry) => (
            <li key={entry.entry.id}>
              <Link className="diary-entry-list__item" to={`/entries/${entry.entry.id}`}>
                <span className="diary-entry-list__name">{entry.entry.sourceName}</span>
                <span className="diary-entry-list__amount">{formatDiaryNumber(entry.entry.amount)} {entry.unitLabel}</span>
                <strong>{formatDiaryNumber(entry.entry.calories)} ккал</strong>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
