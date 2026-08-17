import { Fragment, useLayoutEffect, useRef, type ReactNode } from 'react'

import type { DiaryMeal } from '@/application/diary/diary-service'
import type { MealType } from '@/domain/diary/diary-entry'

import { formatDiaryNumber, getMealTypeLabel } from './diary-formatters'
import { SwipeableDiaryEntry, type DiaryEntryDragStart } from './swipeable-diary-entry'

export interface DiaryDragState {
  entryId: string
  targetMealType: MealType
  targetIndex: number
}

interface MealSectionProps {
  mealType: MealType
  meal: DiaryMeal
  onAdd: () => void
  openEntryId: string | undefined
  deletingEntryId: string | undefined
  onOpenEntryChange: (entryId: string | undefined) => void
  onEntryInteract: (entryId: string) => void
  onDeleteEntry: (entryId: string) => void
  dragState: DiaryDragState | undefined
  onDragStart: (dragStart: DiaryEntryDragStart) => void
  onDropTargetMount: (mealType: MealType, element: HTMLElement | null) => void
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
  dragState,
  onDragStart,
  onDropTargetMount,
}: MealSectionProps) {
  const isDropTarget = dragState?.targetMealType === mealType
  const visibleEntries = dragState === undefined
    ? meal.entries
    : meal.entries.filter((item) => item.entry.id !== dragState.entryId)
  const isEmpty = visibleEntries.length === 0 && !isDropTarget
  const layoutVersion = dragState === undefined
    ? 'idle'
    : `${dragState.entryId}:${dragState.targetMealType}:${dragState.targetIndex}`

  return (
    <section
      ref={(element) => onDropTargetMount(mealType, element)}
      className={isEmpty ? 'meal-section meal-section--empty' : 'meal-section'}
      aria-labelledby={`meal-${mealType}`}
    >
      <div className="meal-section__header">
        <div>
          <h2 id={`meal-${mealType}`}>{getMealTypeLabel(mealType)}</h2>
          <p>{formatDiaryNumber(meal.totals.calories)} ккал</p>
        </div>
        <button className="button button--secondary button--small" type="button" onClick={onAdd}>Добавить</button>
      </div>
      {isEmpty ? null : (
        <ul className="diary-entry-list">
          {visibleEntries.map((entry, index) => (
            <Fragment key={entry.entry.id}>
              {isDropTarget && dragState.targetIndex === index ? <li><DiaryEntryDropPlaceholder /></li> : null}
              <AnimatedDiaryEntryListItem layoutVersion={layoutVersion}>
                <SwipeableDiaryEntry
                  item={entry}
                  isOpen={openEntryId === entry.entry.id}
                  isDeleting={deletingEntryId === entry.entry.id}
                  isDragActive={dragState !== undefined}
                  onOpenChange={onOpenEntryChange}
                  onInteract={onEntryInteract}
                  onDelete={onDeleteEntry}
                  onDragStart={onDragStart}
                />
              </AnimatedDiaryEntryListItem>
            </Fragment>
          ))}
          {isDropTarget && dragState.targetIndex >= visibleEntries.length ? <li><DiaryEntryDropPlaceholder /></li> : null}
        </ul>
      )}
    </section>
  )
}

function DiaryEntryDropPlaceholder() {
  return <div className="diary-entry-drop-placeholder" aria-hidden="true" />
}

function AnimatedDiaryEntryListItem({ children, layoutVersion }: { children: ReactNode; layoutVersion: string }) {
  const itemRef = useRef<HTMLLIElement>(null)
  const previousTopRef = useRef<number | undefined>(undefined)

  useLayoutEffect(() => {
    const element = itemRef.current

    if (element === null) {
      return
    }

    const top = element.getBoundingClientRect().top
    const previousTop = previousTopRef.current
    previousTopRef.current = top

    if (previousTop === undefined || Math.abs(previousTop - top) < 1) {
      return
    }

    element.style.transition = 'none'
    element.style.transform = `translateY(${previousTop - top}px)`
    const animationFrameId = window.requestAnimationFrame(() => {
      element.style.transition = 'transform 180ms ease-out'
      element.style.transform = ''
    })

    return () => window.cancelAnimationFrame(animationFrameId)
  }, [layoutVersion])

  return <li ref={itemRef}>{children}</li>
}
