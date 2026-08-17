import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'

import type { DiaryFoodSource } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'

import {
  getDiaryAddContext,
  getDiaryAddSelectionPath,
  getDiaryFoodSourceType,
  getDiaryPath,
} from './diary-add-routes'
import { DiaryAmountView } from './diary-amount-view'
import { isPositiveDiaryAmount } from './diary-amount-utils'

interface DiaryAmountNavigationState {
  diaryAddSelectionInHistory?: boolean
}

/** Full-screen amount and unit form that creates one immutable Diary snapshot. */
export function FoodAmountPage() {
  const { date, mealType, sourceType, sourceId } = useParams()
  const context = getDiaryAddContext(date, mealType)
  const resolvedSourceType = getDiaryFoodSourceType(sourceType)
  const navigate = useNavigate()
  const location = useLocation()
  const [source, setSource] = useState<DiaryFoodSource | undefined>()
  const [unit, setUnit] = useState('')
  const [amount, setAmount] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | undefined>()
  const isSubmittingRef = useRef(false)

  useEffect(() => {
    let isMounted = true

    async function loadSource(): Promise<void> {
      setIsLoading(true)
      setError(undefined)
      setSource(undefined)
      setUnit('')
      setAmount('')

      if (resolvedSourceType === undefined || sourceId === undefined) {
        setIsLoading(false)
        return
      }

      try {
        const foodSource = await applicationServices.diary.getFoodSource(resolvedSourceType, sourceId)

        if (isMounted && foodSource !== undefined) {
          const [defaultUnit] = applicationServices.diary.getFoodUnitOptions(foodSource)
          setSource(foodSource)
          setUnit(defaultUnit.value)
          setAmount(String(getDefaultAmount(foodSource)))
        }
      } catch (loadError) {
        console.error('Failed to load food source for diary.', loadError)

        if (isMounted) {
          setError('Не удалось загрузить еду. Попробуйте ещё раз.')
        }
      } finally {
        if (isMounted) {
          setIsLoading(false)
        }
      }
    }

    void loadSource()

    return () => {
      isMounted = false
    }
  }, [resolvedSourceType, sourceId])

  const preview = useMemo(() => {
    if (source === undefined || unit === '' || !isPositiveDiaryAmount(amount)) {
      return undefined
    }

    try {
      return applicationServices.diary.previewFoodSource(source, Number(amount), unit)
    } catch {
      return undefined
    }
  }, [amount, source, unit])

  if (context === undefined) {
    return <InvalidDiaryAddContext />
  }

  const addContext = context
  const selectionPath = getDiaryAddSelectionPath(addContext)
  const state = location.state as DiaryAmountNavigationState | null

  function returnToSelection(): void {
    if (state?.diaryAddSelectionInHistory === true) {
      navigate(-1)
      return
    }

    navigate(selectionPath, { replace: true })
  }

  async function addFood(): Promise<void> {
    if (isSubmittingRef.current || source === undefined || preview === undefined) {
      return
    }

    isSubmittingRef.current = true
    setIsSaving(true)
    setError(undefined)

    try {
      if (source.sourceType === 'product') {
        await applicationServices.diary.addProduct({
          date: addContext.date,
          mealType: addContext.mealType,
          productId: source.product.id,
          amount: Number(amount),
          unit,
        })
      } else {
        await applicationServices.diary.addRecipe({
          date: addContext.date,
          mealType: addContext.mealType,
          recipeId: source.recipe.id,
          amount: Number(amount),
          unit,
        })
      }

      navigate(getDiaryPath(addContext.date), { replace: true })
    } catch (addError) {
      console.error('Failed to add food to diary.', addError)
      setError('Не удалось добавить еду. Проверьте количество и попробуйте ещё раз.')
      isSubmittingRef.current = false
      setIsSaving(false)
    }
  }

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  if (source === undefined) {
    return (
      <section className="empty-state" aria-labelledby="diary-product-missing-title">
        <h1 id="diary-product-missing-title">Еда не найдена</h1>
        <p>{error ?? 'Возможно, продукт или блюдо было удалено.'}</p>
        <Link className="button button--secondary" to={selectionPath}>К выбору продуктов</Link>
      </section>
    )
  }

  return (
    <DiaryAmountView
      mode="create"
      sourceName={getSourceName(source)}
      amount={amount}
      unit={unit}
      unitOptions={applicationServices.diary.getFoodUnitOptions(source)}
      nutrition={preview}
      isSaving={isSaving}
      error={error}
      onAmountChange={setAmount}
      onUnitChange={setUnit}
      onSubmit={() => void addFood()}
      onBack={returnToSelection}
    />
  )
}

function InvalidDiaryAddContext() {
  return (
    <section className="empty-state" aria-labelledby="diary-add-context-error-title">
      <h1 id="diary-add-context-error-title">Не удалось открыть добавление еды</h1>
      <p>Дата или приём пищи в ссылке некорректны.</p>
      <Link className="button button--secondary" to="/">К дневнику</Link>
    </section>
  )
}

function getSourceName(source: DiaryFoodSource): string {
  return source.sourceType === 'product' ? source.product.name : source.recipe.name
}

function getDefaultAmount(source: DiaryFoodSource): number {
  if (source.sourceType === 'product') {
    return source.currentVersion.baseAmount
  }

  return source.currentVersion.cookedWeight === undefined ? 1 : 100
}
