import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'

import type { DiaryEntryDetails } from '@/application/diary/diary-service'
import { BackLink } from '@/app/layout/back-link'
import { applicationServices } from '@/app/providers/application-services'
import type { MealType } from '@/domain/diary/diary-entry'

import { getDiaryPath } from './diary-add-routes'
import { formatDiaryNumber, getMealTypeLabel, mealTypes } from './diary-formatters'

export function DiaryEntryDetailsPage() {
  const { entryId } = useParams()
  const navigate = useNavigate()
  const [details, setDetails] = useState<DiaryEntryDetails | undefined>()
  const [mealType, setMealType] = useState<MealType>('breakfast')
  const [unit, setUnit] = useState('')
  const [amount, setAmount] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const [error, setError] = useState<string | undefined>()

  useEffect(() => {
    let isMounted = true

    async function loadEntry(): Promise<void> {
      if (entryId === undefined) {
        setIsLoading(false)
        return
      }

      try {
        const entryDetails = await applicationServices.diary.getEntryDetails(entryId)

        if (isMounted) {
          setDetails(entryDetails)
          setMealType(entryDetails?.entry.mealType ?? 'breakfast')
          setUnit(entryDetails?.entry.unit ?? '')
          setAmount(entryDetails === undefined ? '' : String(entryDetails.entry.amount))
        }
      } catch (loadError) {
        console.error('Failed to load diary entry.', loadError)

        if (isMounted) {
          setError('Не удалось загрузить запись дневника.')
        }
      } finally {
        if (isMounted) {
          setIsLoading(false)
        }
      }
    }

    void loadEntry()

    return () => {
      isMounted = false
    }
  }, [entryId])

  const preview = useMemo(() => {
    if (details === undefined || !isPositiveDecimal(amount) || unit === '') {
      return undefined
    }

    try {
      return applicationServices.diary.previewEntry(details, Number(amount), unit)
    } catch {
      return undefined
    }
  }, [amount, details, unit])

  async function save(): Promise<void> {
    if (entryId === undefined || preview === undefined) {
      return
    }

    setIsSaving(true)
    setError(undefined)

    try {
      const entry = await applicationServices.diary.updateEntry(entryId, { mealType, unit, amount: Number(amount) })
      navigate(getDiaryPath(entry.date), { replace: true })
    } catch (saveError) {
      console.error('Failed to update diary entry.', saveError)
      setError('Не удалось сохранить запись. Проверьте данные и попробуйте ещё раз.')
      setIsSaving(false)
    }
  }

  async function deleteEntry(): Promise<void> {
    if (entryId === undefined || details === undefined) {
      return
    }

    setIsDeleting(true)
    setError(undefined)

    try {
      await applicationServices.diary.softDeleteEntry(entryId)
      navigate(getDiaryPath(details.entry.date), { replace: true })
    } catch (deleteError) {
      console.error('Failed to delete diary entry.', deleteError)
      setError('Не удалось удалить запись. Попробуйте ещё раз.')
      setIsDeleting(false)
    }
  }

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  if (details === undefined) {
    return (
      <section className="empty-state" aria-labelledby="diary-entry-not-found-title">
        <h1 id="diary-entry-not-found-title">Запись не найдена</h1>
        <p>{error ?? 'Возможно, она была удалена.'}</p>
        <Link className="button button--secondary" to="/">К дневнику</Link>
      </section>
    )
  }

  return (
    <section className="diary-entry-details" aria-labelledby="diary-entry-title">
      <BackLink to={getDiaryPath(details.entry.date)} />
      <div className="page-heading">
        <div>
          <h1 id="diary-entry-title">{details.entry.sourceName}</h1>
          <p>Версия {details.entry.sourceType === 'recipe' ? 'рецепта' : 'продукта'} v{details.sourceVersion.versionNumber}</p>
        </div>
      </div>
      <div className="diary-entry-form">
        <div className="form-field">
          <label htmlFor="diary-entry-meal">Приём пищи</label>
          <select id="diary-entry-meal" value={mealType} onChange={(event) => setMealType(event.target.value as MealType)}>
            {mealTypes.map((type) => <option key={type} value={type}>{getMealTypeLabel(type)}</option>)}
          </select>
        </div>
        <div className="form-field">
          <label htmlFor="diary-entry-unit">Единица</label>
          <select id="diary-entry-unit" value={unit} onChange={(event) => setUnit(event.target.value)}>
            {details.unitOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </div>
        <div className="form-field">
          <label htmlFor="diary-entry-amount">Количество</label>
          <input id="diary-entry-amount" type="number" inputMode="decimal" min="0" step="any" value={amount} onChange={(event) => setAmount(event.target.value)} />
          {!isPositiveDecimal(amount) && amount !== '' ? <span className="field-error">Количество должно быть больше нуля.</span> : null}
        </div>
        <EntryNutritionPreview nutrition={preview} />
        {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
        <div className="form-actions">
          <button className="button button--danger" type="button" disabled={isDeleting} onClick={() => void deleteEntry()}>{isDeleting ? 'Удаление…' : 'Удалить'}</button>
          <button className="button button--primary" type="button" disabled={preview === undefined || isSaving} onClick={() => void save()}>{isSaving ? 'Сохранение…' : 'Сохранить'}</button>
        </div>
      </div>
    </section>
  )
}

function EntryNutritionPreview({ nutrition }: { nutrition: { calories: number; protein: number; fat: number; carbs: number } | undefined }) {
  if (nutrition === undefined) {
    return <p className="nutrition-preview nutrition-preview--empty">Укажите корректное количество.</p>
  }

  return (
    <dl className="nutrition-preview">
      <div><dt>Калории</dt><dd>{formatDiaryNumber(nutrition.calories)} ккал</dd></div>
      <div><dt>Белки</dt><dd>{formatDiaryNumber(nutrition.protein)} г</dd></div>
      <div><dt>Жиры</dt><dd>{formatDiaryNumber(nutrition.fat)} г</dd></div>
      <div><dt>Углеводы</dt><dd>{formatDiaryNumber(nutrition.carbs)} г</dd></div>
    </dl>
  )
}

function isPositiveDecimal(value: string): boolean {
  const amount = Number(value)
  return Number.isFinite(amount) && amount > 0
}
