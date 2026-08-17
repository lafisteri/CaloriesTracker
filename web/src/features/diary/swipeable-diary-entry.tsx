import { useEffect, useRef, useState, type MouseEvent, type PointerEvent } from 'react'
import { Link } from 'react-router-dom'

import type { DiaryEntryListItem } from '@/application/diary/diary-service'

import { formatDiaryNumber } from './diary-formatters'

const deleteActionWidth = 96
const swipeThreshold = deleteActionWidth / 2
const gestureIntentThreshold = 8
const longPressDelay = 420

type SwipeAxis = 'horizontal' | 'vertical'

interface SwipeGesture {
  pointerId: number
  startX: number
  startY: number
  startOffset: number
  offset: number
  axis?: SwipeAxis
}

interface LongPressGesture {
  pointerId: number
  startX: number
  startY: number
  timerId: number
}

export interface DiaryEntryDragStart {
  entryId: string
  item: DiaryEntryListItem
  pointerId: number
  pointerType: string
  clientX: number
  clientY: number
  pointerOffsetX: number
  pointerOffsetY: number
  rect: Pick<DOMRect, 'left' | 'top' | 'width' | 'height'>
}

interface SwipeableDiaryEntryProps {
  item: DiaryEntryListItem
  isOpen: boolean
  isDeleting: boolean
  isDragActive: boolean
  onOpenChange: (entryId: string | undefined) => void
  onInteract: (entryId: string) => void
  onDelete: (entryId: string) => void
  onDragStart: (dragStart: DiaryEntryDragStart) => void
}

/** Touch-friendly Diary row supporting quick horizontal delete swipes and long-press drag. */
export function SwipeableDiaryEntry({
  item,
  isOpen,
  isDeleting,
  isDragActive,
  onOpenChange,
  onInteract,
  onDelete,
  onDragStart,
}: SwipeableDiaryEntryProps) {
  const entryId = item.entry.id
  const rootRef = useRef<HTMLDivElement>(null)
  const gestureRef = useRef<SwipeGesture | undefined>(undefined)
  const longPressRef = useRef<LongPressGesture | undefined>(undefined)
  const hasStartedDragRef = useRef(false)
  const suppressClickRef = useRef(false)
  const [dragOffset, setDragOffset] = useState<number | undefined>()
  const offset = dragOffset ?? (isOpen ? -deleteActionWidth : 0)

  useEffect(() => () => clearLongPress(), [])

  function handlePointerDown(event: PointerEvent<HTMLDivElement>): void {
    onInteract(entryId)

    if (isDragActive || !event.isPrimary || event.button !== 0 || event.target instanceof HTMLButtonElement) {
      return
    }

    hasStartedDragRef.current = false
    scheduleLongPress(event)

    if (event.pointerType !== 'mouse') {
      gestureRef.current = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        startOffset: isOpen ? -deleteActionWidth : 0,
        offset: isOpen ? -deleteActionWidth : 0,
      }
    }
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>): void {
    const longPress = longPressRef.current

    if (longPress?.pointerId === event.pointerId && movedBeyondGestureThreshold(event, longPress)) {
      clearLongPress()
    }

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

      clearLongPress()
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
    clearLongPress(event.pointerId)

    if (hasStartedDragRef.current) {
      hasStartedDragRef.current = false
      suppressFollowingClick()
      return
    }

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
    clearLongPress(event.pointerId)

    if (hasStartedDragRef.current) {
      hasStartedDragRef.current = false
      return
    }

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

  function scheduleLongPress(event: PointerEvent<HTMLDivElement>): void {
    clearLongPress()
    const pointerId = event.pointerId
    const pointerType = event.pointerType

    const timerId = window.setTimeout(() => {
      const longPress = longPressRef.current
      const element = rootRef.current

      if (longPress === undefined || longPress.pointerId !== pointerId || element === null) {
        return
      }

      longPressRef.current = undefined
      gestureRef.current = undefined
      hasStartedDragRef.current = true
      const rect = element.getBoundingClientRect()
      onOpenChange(undefined)
      onDragStart({
        entryId,
        item,
        pointerId,
        pointerType,
        clientX: longPress.startX,
        clientY: longPress.startY,
        pointerOffsetX: longPress.startX - rect.left,
        pointerOffsetY: longPress.startY - rect.top,
        rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
      })
    }, longPressDelay)

    longPressRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      timerId,
    }
  }

  function clearLongPress(pointerId?: number): void {
    const longPress = longPressRef.current

    if (longPress === undefined || (pointerId !== undefined && longPress.pointerId !== pointerId)) {
      return
    }

    window.clearTimeout(longPress.timerId)
    longPressRef.current = undefined
  }

  function suppressFollowingClick(): void {
    suppressClickRef.current = true
    window.setTimeout(() => {
      suppressClickRef.current = false
    }, 0)
  }

  return (
    <div
      ref={rootRef}
      className="diary-entry-swipe"
      data-diary-entry-id={entryId}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerEnd}
      onPointerCancel={handlePointerCancel}
      onClickCapture={handleClickCapture}
      onContextMenu={(event) => event.preventDefault()}
    >
      <button
        className="button button--danger button--small diary-entry-swipe__delete"
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
        <DiaryEntryRowContent item={item} />
      </Link>
    </div>
  )
}

export function DiaryEntryRowContent({ item }: { item: DiaryEntryListItem }) {
  return (
    <>
      <span className="diary-entry-list__name">{item.entry.sourceName}</span>
      <span className="diary-entry-list__amount">{formatDiaryNumber(item.entry.amount)} {item.unitLabel}</span>
      <strong>{formatDiaryNumber(item.entry.calories)} ккал</strong>
    </>
  )
}

function movedBeyondGestureThreshold(event: PointerEvent<HTMLDivElement>, gesture: Pick<LongPressGesture, 'startX' | 'startY'>): boolean {
  return Math.abs(event.clientX - gesture.startX) >= gestureIntentThreshold
    || Math.abs(event.clientY - gesture.startY) >= gestureIntentThreshold
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum)
}
