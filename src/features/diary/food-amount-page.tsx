import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'

import type { DiaryProduct } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'
import { getDiaryUnitOptions } from '@/domain/diary/diary-unit'

import {
  getDiaryAddContext,
  getDiaryAddSelectionPath,
  getDiaryPath,
} from './diary-add-routes'
import { formatDiaryNumber, formatDiaryShortDate, getMealTypeLabel } from './diary-formatters'

interface DiaryAmountNavigationState {
  diaryAddSelectionInHistory?: boolean
}

/** Full-screen amount and unit form that creates one immutable Diary snapshot. */
export function FoodAmountPage() {
  const { date, mealType, productId } = useParams()
  const context = getDiaryAddContext(date, mealType)
  const navigate = useNavigate()
  const location = useLocation()
  const [product, setProduct] = useState<DiaryProduct | undefined>()
  const [unit, setUnit] = useState('')
  const [amount, setAmount] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | undefined>()
  const isSubmittingRef = useRef(false)

  useEffect(() => {
    let isMounted = true

    async function loadProduct(): Promise<void> {
      setIsLoading(true)
      setError(undefined)
      setProduct(undefined)
      setUnit('')
      setAmount('')

      if (productId === undefined) {
        setIsLoading(false)
        return
      }

      try {
        const details = await applicationServices.products.getById(productId)

        if (isMounted && details !== undefined) {
          const diaryProduct = { product: details.product, currentVersion: details.currentVersion }
          const [defaultUnit] = getDiaryUnitOptions(diaryProduct.currentVersion)
          setProduct(diaryProduct)
          setUnit(defaultUnit.value)
          setAmount(String(diaryProduct.currentVersion.baseAmount))
        }
      } catch (loadError) {
        console.error('Failed to load product for diary.', loadError)

        if (isMounted) {
          setError('Не удалось загрузить продукт. Попробуйте ещё раз.')
        }
      } finally {
        if (isMounted) {
          setIsLoading(false)
        }
      }
    }

    void loadProduct()

    return () => {
      isMounted = false
    }
  }, [productId])

  const preview = useMemo(() => {
    if (product === undefined || unit === '' || !isPositiveDecimal(amount)) {
      return undefined
    }

    try {
      return applicationServices.diary.previewProduct(product, Number(amount), unit)
    } catch {
      return undefined
    }
  }, [amount, product, unit])

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

  async function addProduct(): Promise<void> {
    if (isSubmittingRef.current || product === undefined || preview === undefined) {
      return
    }

    isSubmittingRef.current = true
    setIsSaving(true)
    setError(undefined)

    try {
      await applicationServices.diary.addProduct({
        date: addContext.date,
        mealType: addContext.mealType,
        productId: product.product.id,
        amount: Number(amount),
        unit,
      })

      if (state?.diaryAddSelectionInHistory === true) {
        navigate(-2)
      } else {
        navigate(getDiaryPath(addContext.date), { replace: true })
      }
    } catch (addError) {
      console.error('Failed to add diary product.', addError)
      setError('Не удалось добавить продукт. Проверьте количество и попробуйте ещё раз.')
      isSubmittingRef.current = false
      setIsSaving(false)
    }
  }

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  if (product === undefined) {
    return (
      <section className="empty-state" aria-labelledby="diary-product-missing-title">
        <h1 id="diary-product-missing-title">Продукт не найден</h1>
        <p>{error ?? 'Возможно, продукт был удалён.'}</p>
        <Link className="button button--secondary" to={selectionPath}>К выбору продуктов</Link>
      </section>
    )
  }

  return (
    <section className="diary-add-page" aria-labelledby="food-amount-title">
      <header className="diary-add-page__header">
        <button className="back-link diary-add-page__back" type="button" onClick={returnToSelection}>‹ {product.product.name}</button>
        <span>{formatDiaryShortDate(addContext.date)}</span>
      </header>
      <div className="diary-add-page__scroll diary-amount-page__scroll">
        <div className="diary-add-page__intro">
          <h1 id="food-amount-title">{product.product.name}</h1>
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
              {getDiaryUnitOptions(product.currentVersion).map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          </div>
          <NutritionPreview nutrition={preview} />
          {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
          <div className="diary-add-page__actions">
            <button className="button button--primary" type="button" disabled={preview === undefined || isSaving} onClick={() => void addProduct()}>
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
