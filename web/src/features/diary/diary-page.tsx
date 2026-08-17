import { useCallback, useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'

import type { DiaryDay } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'
import type { MealType } from '@/domain/diary/diary-entry'
import type { DailyMacroGoal } from '@/domain/goals/weekly-goal'
import { toLocalDateKey, shiftLocalDateKey } from '@/shared/utils/local-date-key'

import { getDiaryAddSelectionPath, getDiaryDateFromSearch, getDiaryPath } from './diary-add-routes'
import { DiaryDateNavigation } from './diary-date-navigation'
import { DailyGoalSummary } from './daily-goal-summary'
import { mealTypes } from './diary-formatters'
import { MealSection, type DiaryDragState } from './meal-section'
import { DiaryEntryRowContent, type DiaryEntryDragStart } from './swipeable-diary-entry'

const autoScrollEdge = 88
const autoScrollMaxStep = 10

interface ActiveDiaryDrag extends DiaryDragState, DiaryEntryDragStart {
  date: string
}

export function DiaryPage() {
  const location = useLocation()
  const navigate = useNavigate()
  const date = getDiaryDateFromSearch(location.search) ?? toLocalDateKey()
  const [day, setDay] = useState<DiaryDay | undefined>()
  const [dailyGoal, setDailyGoal] = useState<DailyMacroGoal | undefined>()
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const [deleteError, setDeleteError] = useState<string | undefined>()
  const [reorderError, setReorderError] = useState<string | undefined>()
  const [openEntryId, setOpenEntryId] = useState<string | undefined>()
  const [deletingEntryId, setDeletingEntryId] = useState<string | undefined>()
  const [drag, setDrag] = useState<ActiveDiaryDrag | undefined>()
  const [isReordering, setIsReordering] = useState(false)
  const isDragging = drag !== undefined
  const loadRequestId = useRef(0)
  const activeDragRef = useRef<ActiveDiaryDrag | undefined>(undefined)
  const mealTargetsRef = useRef(new Map<MealType, HTMLElement>())
  const suppressFollowingClickRef = useRef(false)

  const loadDay = useCallback(async (dateKey: string, showLoading = true) => {
    const requestId = ++loadRequestId.current
    if (showLoading) {
      setIsLoading(true)
    }
    setError(undefined)

    try {
      const [loadedDay, loadedGoal] = await Promise.all([
        applicationServices.diary.getDay(dateKey),
        applicationServices.goals.getGoalForDate(dateKey),
      ])

      if (requestId === loadRequestId.current) {
        setDay(loadedDay)
        setDailyGoal(loadedGoal)
      }
    } catch (loadError) {
      console.error('Failed to load diary day.', loadError)

      if (requestId === loadRequestId.current) {
        setError('Не удалось загрузить дневник. Попробуйте ещё раз.')
      }
    } finally {
      if (requestId === loadRequestId.current) {
        if (showLoading) {
          setIsLoading(false)
        }
      }
    }
  }, [])

  const findDropTarget = useCallback((entryId: string, clientX: number, clientY: number): Pick<DiaryDragState, 'targetMealType' | 'targetIndex'> | undefined => {
    const mealTarget = [...mealTargetsRef.current.entries()]
      .map(([mealType, element]) => ({ mealType, element, rect: element.getBoundingClientRect() }))
      .sort((left, right) => distanceToRect(clientX, clientY, left.rect) - distanceToRect(clientX, clientY, right.rect))[0]

    if (mealTarget === undefined) {
      return undefined
    }

    const entryElements = [...mealTarget.element.querySelectorAll<HTMLElement>('[data-diary-entry-id]')]
      .filter((element) => element.dataset.diaryEntryId !== entryId)
    const targetIndex = entryElements.findIndex((element) => {
      const rect = element.getBoundingClientRect()
      return clientY < rect.top + rect.height / 2
    })

    return {
      targetMealType: mealTarget.mealType,
      targetIndex: targetIndex === -1 ? entryElements.length : targetIndex,
    }
  }, [])

  const updateDragPosition = useCallback((clientX: number, clientY: number) => {
    const currentDrag = activeDragRef.current

    if (currentDrag === undefined) {
      return
    }

    const dropTarget = findDropTarget(currentDrag.entryId, clientX, clientY) ?? {
      targetMealType: currentDrag.targetMealType,
      targetIndex: currentDrag.targetIndex,
    }
    const nextDrag: ActiveDiaryDrag = { ...currentDrag, ...dropTarget, clientX, clientY }
    activeDragRef.current = nextDrag
    setDrag(nextDrag)
  }, [findDropTarget])

  const cancelDrag = useCallback(() => {
    activeDragRef.current = undefined
    setDrag(undefined)
  }, [])

  const completeDrag = useCallback((dragToSave: ActiveDiaryDrag) => {
    activeDragRef.current = undefined
    setDrag(undefined)
    suppressFollowingClickRef.current = true
    window.setTimeout(() => {
      suppressFollowingClickRef.current = false
    }, 0)
    setIsReordering(true)
    setReorderError(undefined)

    void (async () => {
      try {
        await applicationServices.diary.moveEntry(dragToSave.entryId, dragToSave.targetMealType, dragToSave.targetIndex)
      } catch (moveError) {
        console.error('Failed to reorder diary entry.', moveError)
        setReorderError('Не удалось изменить порядок записей. Попробуйте ещё раз.')
      } finally {
        await loadDay(dragToSave.date, false)
        setIsReordering(false)
      }
    })()
  }, [loadDay])

  useEffect(() => {
    function handlePointerMove(event: PointerEvent): void {
      const currentDrag = activeDragRef.current

      if (currentDrag === undefined || currentDrag.pointerId !== event.pointerId) {
        return
      }

      event.preventDefault()
      updateDragPosition(event.clientX, event.clientY)
    }

    function handlePointerUp(event: PointerEvent): void {
      const currentDrag = activeDragRef.current

      if (currentDrag === undefined || currentDrag.pointerId !== event.pointerId) {
        return
      }

      completeDrag(currentDrag)
    }

    function handlePointerCancel(event: PointerEvent): void {
      const currentDrag = activeDragRef.current

      if (currentDrag?.pointerId === event.pointerId && currentDrag.pointerType !== 'touch') {
        cancelDrag()
      }
    }

    function handleTouchMove(event: TouchEvent): void {
      const currentDrag = activeDragRef.current

      if (currentDrag?.pointerType !== 'touch') {
        return
      }

      const touch = event.touches[0]

      if (touch === undefined) {
        return
      }

      event.preventDefault()
      updateDragPosition(touch.clientX, touch.clientY)
    }

    function handleTouchEnd(): void {
      const currentDrag = activeDragRef.current

      if (currentDrag?.pointerType === 'touch') {
        completeDrag(currentDrag)
      }
    }

    function handleTouchCancel(): void {
      if (activeDragRef.current?.pointerType === 'touch') {
        cancelDrag()
      }
    }

    window.addEventListener('pointermove', handlePointerMove, { passive: false, capture: true })
    window.addEventListener('pointerup', handlePointerUp)
    window.addEventListener('pointercancel', handlePointerCancel)
    window.addEventListener('touchmove', handleTouchMove, { passive: false, capture: true })
    window.addEventListener('touchend', handleTouchEnd, { capture: true })
    window.addEventListener('touchcancel', handleTouchCancel, { capture: true })

    return () => {
      window.removeEventListener('pointermove', handlePointerMove, true)
      window.removeEventListener('pointerup', handlePointerUp)
      window.removeEventListener('pointercancel', handlePointerCancel)
      window.removeEventListener('touchmove', handleTouchMove, true)
      window.removeEventListener('touchend', handleTouchEnd, true)
      window.removeEventListener('touchcancel', handleTouchCancel, true)
    }
  }, [cancelDrag, completeDrag, updateDragPosition])

  useEffect(() => {
    function suppressDragClick(event: MouseEvent): void {
      if (!suppressFollowingClickRef.current) {
        return
      }

      suppressFollowingClickRef.current = false
      event.preventDefault()
      event.stopImmediatePropagation()
    }

    document.addEventListener('click', suppressDragClick, true)
    return () => document.removeEventListener('click', suppressDragClick, true)
  }, [])

  useEffect(() => {
    if (!isDragging) {
      return
    }

    const intervalId = window.setInterval(() => {
      const currentDrag = activeDragRef.current

      if (currentDrag === undefined) {
        return
      }

      const scrollStep = getAutoScrollStep(currentDrag.clientY)

      if (scrollStep === 0) {
        return
      }

      window.scrollBy({ top: scrollStep })
      updateDragPosition(currentDrag.clientX, currentDrag.clientY)
    }, 16)

    return () => window.clearInterval(intervalId)
  }, [isDragging, updateDragPosition])

  useEffect(() => {
    void loadDay(date)
    cancelDrag()
  }, [cancelDrag, date, loadDay])

  function changeDate(nextDate: string): void {
    cancelDrag()
    setOpenEntryId(undefined)
    navigate(getDiaryPath(nextDate), { replace: true })
  }

  function handleEntryInteract(entryId: string): void {
    if (openEntryId !== undefined && openEntryId !== entryId) {
      setOpenEntryId(undefined)
    }
  }

  function handleDragStart(dragStart: DiaryEntryDragStart): void {
    if (day === undefined || isReordering) {
      return
    }

    const mealEntries = day.meals[dragStart.item.entry.mealType].entries
    const sourceIndex = mealEntries.findIndex((item) => item.entry.id === dragStart.entryId)

    if (sourceIndex === -1) {
      return
    }

    const nextDrag: ActiveDiaryDrag = {
      ...dragStart,
      date,
      targetMealType: dragStart.item.entry.mealType,
      targetIndex: sourceIndex,
    }
    activeDragRef.current = nextDrag
    setOpenEntryId(undefined)
    setReorderError(undefined)
    setDrag(nextDrag)
  }

  function handleDropTargetMount(mealType: MealType, element: HTMLElement | null): void {
    if (element === null) {
      mealTargetsRef.current.delete(mealType)
      return
    }

    mealTargetsRef.current.set(mealType, element)
  }

  async function deleteEntry(entryId: string): Promise<void> {
    if (deletingEntryId !== undefined || drag !== undefined || isReordering) {
      return
    }

    setDeletingEntryId(entryId)
    setDeleteError(undefined)
    setOpenEntryId(undefined)

    try {
      await applicationServices.diary.softDeleteEntry(entryId)
      await loadDay(date, false)
    } catch (deleteEntryError) {
      console.error('Failed to delete diary entry.', deleteEntryError)
      setDeleteError('Не удалось удалить запись. Попробуйте ещё раз.')
    } finally {
      setDeletingEntryId(undefined)
    }
  }

  return (
    <section className="diary-page" aria-labelledby="diary-title">
      <h1 id="diary-title" className="sr-only">Дневник</h1>
      <DiaryDateNavigation
        date={date}
        onChange={changeDate}
        onPrevious={() => changeDate(shiftLocalDateKey(date, -1))}
        onNext={() => changeDate(shiftLocalDateKey(date, 1))}
      />

      {isLoading ? <p className="status-message">Загрузка…</p> : null}
      {error === undefined ? null : (
        <div className="status-message status-message--error" role="alert">
          <p>{error}</p>
          <button className="button button--secondary" type="button" onClick={() => void loadDay(date)}>Повторить</button>
        </div>
      )}
      {deleteError === undefined ? null : <p className="form-submit-error" role="alert">{deleteError}</p>}
      {reorderError === undefined ? null : <p className="form-submit-error" role="alert">{reorderError}</p>}
      {day === undefined || isLoading || error !== undefined ? null : (
        <>
          <DailyGoalSummary date={date} totals={day.totals} goal={dailyGoal} />

          <div className="meal-sections">
            {mealTypes.map((mealType) => (
              <MealSection
                key={mealType}
                mealType={mealType}
                meal={day.meals[mealType]}
                onAdd={() => navigate(getDiaryAddSelectionPath({ date, mealType }), { state: { diaryAddFromDiary: true } })}
                openEntryId={openEntryId}
                deletingEntryId={deletingEntryId}
                onOpenEntryChange={setOpenEntryId}
                onEntryInteract={handleEntryInteract}
                onDeleteEntry={(entryId) => void deleteEntry(entryId)}
                dragState={drag}
                onDragStart={handleDragStart}
                onDropTargetMount={handleDropTargetMount}
              />
            ))}
          </div>
        </>
      )}
      {drag === undefined ? null : <DiaryEntryDragOverlay drag={drag} />}
    </section>
  )
}

function DiaryEntryDragOverlay({ drag }: { drag: ActiveDiaryDrag }) {
  const left = clamp(drag.clientX - drag.pointerOffsetX, 8, window.innerWidth - drag.rect.width - 8)
  const top = drag.clientY - drag.pointerOffsetY

  return (
    <div
      className="diary-entry-list__item diary-entry-drag-overlay"
      aria-hidden="true"
      style={{ width: drag.rect.width, left, top }}
    >
      <DiaryEntryRowContent item={drag.item} />
    </div>
  )
}

function distanceToRect(clientX: number, clientY: number, rect: DOMRect): number {
  const horizontalDistance = clientX < rect.left ? rect.left - clientX : clientX > rect.right ? clientX - rect.right : 0
  const verticalDistance = clientY < rect.top ? rect.top - clientY : clientY > rect.bottom ? clientY - rect.bottom : 0
  return Math.hypot(horizontalDistance, verticalDistance)
}

function getAutoScrollStep(clientY: number): number {
  const topProgress = (autoScrollEdge - clientY) / autoScrollEdge

  if (topProgress > 0) {
    return -Math.ceil(Math.min(topProgress, 1) * autoScrollMaxStep)
  }

  const bottomEdge = window.innerHeight - autoScrollEdge
  const bottomProgress = (clientY - bottomEdge) / autoScrollEdge

  if (bottomProgress > 0) {
    return Math.ceil(Math.min(bottomProgress, 1) * autoScrollMaxStep)
  }

  return 0
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum)
}
