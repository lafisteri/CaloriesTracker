import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'

import type { DiaryEntryDetails } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'

import { getDiaryPath } from './diary-add-routes'
import { DiaryAmountView } from './diary-amount-view'
import { isPositiveDiaryAmount } from './diary-amount-utils'

/** Edit-mode route controller for the shared Diary amount view. */
export function DiaryEntryDetailsPage() {
  const { entryId } = useParams()
  const navigate = useNavigate()
  const [details, setDetails] = useState<DiaryEntryDetails | undefined>()
  const [unit, setUnit] = useState('')
  const [amount, setAmount] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
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
    if (details === undefined || !isPositiveDiaryAmount(amount) || unit === '') {
      return undefined
    }

    try {
      return applicationServices.diary.previewEntry(details, Number(amount), unit)
    } catch {
      return undefined
    }
  }, [amount, details, unit])

  async function save(): Promise<void> {
    if (entryId === undefined || details === undefined || preview === undefined) {
      return
    }

    setIsSaving(true)
    setError(undefined)

    try {
      const entry = await applicationServices.diary.updateEntry(entryId, { mealType: details.entry.mealType, unit, amount: Number(amount) })
      navigate(getDiaryPath(entry.date), { replace: true })
    } catch (saveError) {
      console.error('Failed to save diary entry.', saveError)
      setError('Не удалось сохранить запись. Проверьте данные и попробуйте ещё раз.')
      setIsSaving(false)
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
    <DiaryAmountView
      mode="edit"
      sourceName={details.entry.sourceName}
      amount={amount}
      unit={unit}
      unitOptions={details.unitOptions}
      nutrition={preview}
      isSaving={isSaving}
      error={error}
      onAmountChange={setAmount}
      onUnitChange={setUnit}
      onSubmit={() => void save()}
      onBack={() => navigate(getDiaryPath(details.entry.date))}
    />
  )
}
