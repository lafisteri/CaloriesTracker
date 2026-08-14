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
import { formatDiaryNumber, formatDiaryShortDate, getMealTypeLabel } from './diary-formatters'

interface DiaryAmountNavigationState {
  diaryAddSelectionInHistory?: boolean
}

/** Full-screen amount and unit form that creates one immutable Diary snapshot. */
export function FoodAmountPage() {
  const { date, mealType, sourceType, sourceId } = useParams()
  const context = getDiaryAddContext(date, mealType)
  // Keep old product-only links working, but never reinterpret an invalid typed URL as a product.
  const resolvedSourceType = sourceType === undefined
    ? (sourceId === undefined ? undefined : 'product')
    : getDiaryFoodSourceType(sourceType)
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
    if (source === undefined || unit === '' || !isPositiveDecimal(amount)) {
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

      if (state?.diaryAddSelectionInHistory === true) {
        navigate(-2)
      } else {
        navigate(getDiaryPath(addContext.date), { replace: true })
      }
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
    <section className="diary-add-page" aria-labelledby="food-amount-title">
      <header className="diary-add-page__header">
        <button className="back-link diary-add-page__back" type="button" onClick={returnToSelection}>‹ {getSourceName(source)}</button>
        <span>{formatDiaryShortDate(addContext.date)}</span>
      </header>
      <div className="diary-add-page__scroll diary-amount-page__scroll">
        <div className="diary-add-page__intro">
          <h1 id="food-amount-title">{getSourceName(source)}</h1>
          <p>Добавить в: <strong>{getMealTypeLabel(addContext.mealType)}</strong></p>
        </div>
        <div className="diary-entry-form">
          <div className="form-field">
            <label htmlFor="diary-add-amount">Количество</label>
            <input id="diary-add-amount" autoFocus type="number" inputMode="decimal" min="0" step="any" value={amount} onChange={(event) => setAmount(event.target.value)} />
            {!isPositiveDecimal(amount) && amount !== '' ? <span className="field-error">Количество должно быть больше нуля.</span> : null}
          </div>
          <div className="form-field">
            <label htmlFor="diary-add-unit">Единица</label>
            <select id="diary-add-unit" value={unit} onChange={(event) => setUnit(event.target.value)}>
              {applicationServices.diary.getFoodUnitOptions(source).map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          </div>
          <NutritionPreview nutrition={preview} />
          {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
          <div className="diary-add-page__actions">
            <button className="button button--primary" type="button" disabled={preview === undefined || isSaving} onClick={() => void addFood()}>
              {isSaving ? 'Добавление…' : `Добавить в ${getMealTypeLabel(addContext.mealType).toLocaleLowerCase()}`}
            </button>
          </div>
        </div>
      </div>
    </section>
  )
}

function NutritionPreview({ nutrition }: { nutrition: { calories: number; protein: number; fat: number; carbs: number } | undefined }) {
  if (nutrition === undefined) {
    return <p className="nutrition-preview nutrition-preview--empty">Укажите корректное количество, чтобы увидеть КБЖУ.</p>
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

function InvalidDiaryAddContext() {
  return (
    <section className="empty-state" aria-labelledby="diary-add-context-error-title">
      <h1 id="diary-add-context-error-title">Не удалось открыть добавление еды</h1>
      <p>Дата или приём пищи в ссылке некорректны.</p>
      <Link className="button button--secondary" to="/diary">К дневнику</Link>
    </section>
  )
}

function isPositiveDecimal(value: string): boolean {
  const numericAmount = Number(value)

  return Number.isFinite(numericAmount) && numericAmount > 0
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
