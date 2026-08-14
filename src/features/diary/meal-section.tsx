import type { DiaryMeal } from '@/application/diary/diary-service'
import type { MealType } from '@/domain/diary/diary-entry'

import { formatDiaryNumber, getMealTypeLabel } from './diary-formatters'
import { SwipeableDiaryEntry } from './swipeable-diary-entry'

interface MealSectionProps {
  mealType: MealType
  meal: DiaryMeal
  onAdd: () => void
  openEntryId: string | undefined
  deletingEntryId: string | undefined
  onOpenEntryChange: (entryId: string | undefined) => void
  onEntryInteract: (entryId: string) => void
  onDeleteEntry: (entryId: string) => void
}

export function MealSection({
  mealType,
  meal,
  onAdd,
  openEntryId,
  deletingEntryId,
  onOpenEntryChange,
  onEntryInteract,
  onDeleteEntry,
}: MealSectionProps) {
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
              <SwipeableDiaryEntry
                item={entry}
                isOpen={openEntryId === entry.entry.id}
                isDeleting={deletingEntryId === entry.entry.id}
                onOpenChange={onOpenEntryChange}
                onInteract={onEntryInteract}
                onDelete={onDeleteEntry}
              />
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
