import { useRef, useState, type MouseEvent, type PointerEvent } from 'react'
import { Link } from 'react-router-dom'

import type { DiaryEntryListItem } from '@/application/diary/diary-service'

import { formatDiaryNumber } from './diary-formatters'

const deleteActionWidth = 96
const swipeThreshold = deleteActionWidth / 2
const gestureIntentThreshold = 8

type SwipeAxis = 'horizontal' | 'vertical'

interface SwipeGesture {
  pointerId: number
  startX: number
  startY: number
  startOffset: number
  offset: number
  axis?: SwipeAxis
}

interface SwipeableDiaryEntryProps {
  item: DiaryEntryListItem
  isOpen: boolean
  isDeleting: boolean
  onOpenChange: (entryId: string | undefined) => void
  onInteract: (entryId: string) => void
  onDelete: (entryId: string) => void
}

/** Touch-friendly Diary row that reveals, but never auto-runs, its delete action. */
export function SwipeableDiaryEntry({
  item,
  isOpen,
  isDeleting,
  onOpenChange,
  onInteract,
  onDelete,
}: SwipeableDiaryEntryProps) {
  const entryId = item.entry.id
  const gestureRef = useRef<SwipeGesture | undefined>(undefined)
  const suppressClickRef = useRef(false)
  const [dragOffset, setDragOffset] = useState<number | undefined>()
  const offset = dragOffset ?? (isOpen ? -deleteActionWidth : 0)

  function handlePointerDown(event: PointerEvent<HTMLDivElement>): void {
    onInteract(entryId)

    if (event.pointerType === 'mouse' || event.button !== 0) {
      return
    }

    gestureRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      startOffset: isOpen ? -deleteActionWidth : 0,
      offset: isOpen ? -deleteActionWidth : 0,
    }
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>): void {
    const gesture = gestureRef.current

    if (gesture === undefined || gesture.pointerId !== event.pointerId) {
      return
    }

    const deltaX = event.clientX - gesture.startX
    const deltaY = event.clientY - gesture.startY

    if (gesture.axis === undefined) {
      if (Math.abs(deltaX) < gestureIntentThreshold && Math.abs(deltaY) < gestureIntentThreshold) {
        return
      }

      gesture.axis = Math.abs(deltaX) > Math.abs(deltaY) ? 'horizontal' : 'vertical'

      if (gesture.axis === 'vertical') {
        gestureRef.current = undefined
        return
      }

      event.currentTarget.setPointerCapture(event.pointerId)
    }

    if (gesture.axis !== 'horizontal') {
      return
    }

    event.preventDefault()
    gesture.offset = clamp(gesture.startOffset + deltaX, -deleteActionWidth, 0)
    setDragOffset(gesture.offset)
  }

  function handlePointerEnd(event: PointerEvent<HTMLDivElement>): void {
    const gesture = gestureRef.current

    if (gesture === undefined || gesture.pointerId !== event.pointerId) {
      return
    }

    gestureRef.current = undefined

    if (gesture.axis === 'horizontal') {
      onOpenChange(gesture.offset <= -swipeThreshold ? entryId : undefined)
      suppressFollowingClick()
    }

    setDragOffset(undefined)
  }

  function handlePointerCancel(event: PointerEvent<HTMLDivElement>): void {
    if (gestureRef.current?.pointerId !== event.pointerId) {
      return
    }

    gestureRef.current = undefined
    setDragOffset(undefined)
  }

  function handleClickCapture(event: MouseEvent<HTMLDivElement>): void {
    if (!suppressClickRef.current) {
      return
    }

    suppressClickRef.current = false
    event.preventDefault()
    event.stopPropagation()
  }

  function suppressFollowingClick(): void {
    suppressClickRef.current = true
    window.setTimeout(() => {
      suppressClickRef.current = false
    }, 0)
  }

  return (
    <div
      className="diary-entry-swipe"
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerEnd}
      onPointerCancel={handlePointerCancel}
      onClickCapture={handleClickCapture}
    >
      <button
        className="diary-entry-swipe__delete"
        type="button"
        tabIndex={isOpen ? 0 : -1}
        disabled={isDeleting}
        onClick={() => onDelete(entryId)}
      >
        {isDeleting ? 'Удаление…' : 'Удалить'}
      </button>
      <Link
        className={dragOffset === undefined ? 'diary-entry-list__item diary-entry-list__item--swipe-ready' : 'diary-entry-list__item'}
        to={`/entries/${entryId}`}
        style={{ transform: `translate3d(${offset}px, 0, 0)` }}
      >
        <span className="diary-entry-list__name">{item.entry.sourceName}</span>
        <span className="diary-entry-list__amount">{formatDiaryNumber(item.entry.amount)} {item.unitLabel}</span>
        <strong>{formatDiaryNumber(item.entry.calories)} ккал</strong>
      </Link>
    </div>
  )
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum)
}
