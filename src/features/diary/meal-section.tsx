import { Link } from 'react-router-dom'

import type { DiaryMeal } from '@/application/diary/diary-service'
import type { MealType } from '@/domain/diary/diary-entry'

import { formatDiaryNumber, getMealTypeLabel } from './diary-formatters'

interface MealSectionProps {
  mealType: MealType
  meal: DiaryMeal
  onAdd: (mealType: MealType) => void
}

export function MealSection({ mealType, meal, onAdd }: MealSectionProps) {
  return (
    <section className="meal-section" aria-labelledby={`meal-${mealType}`}>
      <div className="meal-section__header">
        <div>
          <h2 id={`meal-${mealType}`}>{getMealTypeLabel(mealType)}</h2>
          <p>{formatDiaryNumber(meal.totals.calories)} ккал</p>
        </div>
        <button className="button button--secondary button--small" type="button" onClick={() => onAdd(mealType)}>+ Добавить</button>
      </div>
      {meal.entries.length === 0 ? null : (
        <ul className="diary-entry-list">
          {meal.entries.map((entry) => (
            <li key={entry.entry.id}>
              <Link className="diary-entry-list__item" to={`/diary/entries/${entry.entry.id}`}>
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
