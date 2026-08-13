import { useCallback, useEffect, useMemo, useRef, useState } from 'react'

import type { DiaryProduct } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'
import type { MealType } from '@/domain/diary/diary-entry'
import { getDiaryUnitOptions } from '@/domain/diary/diary-unit'
import { formatNutrition } from '@/features/products/product-formatters'

import { formatDiaryNumber, getMealTypeLabel } from './diary-formatters'

interface FoodPickerSheetProps {
  date: string
  mealType: MealType
  onClose: () => void
  onAdded: () => void
}

export function FoodPickerSheet({ date, mealType, onClose, onAdded }: FoodPickerSheetProps) {
  const [query, setQuery] = useState('')
  const [recentProducts, setRecentProducts] = useState<DiaryProduct[]>([])
  const [searchProducts, setSearchProducts] = useState<DiaryProduct[]>([])
  const [selectedProduct, setSelectedProduct] = useState<DiaryProduct | undefined>()
  const [unit, setUnit] = useState('')
  const [amount, setAmount] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | undefined>()
  const searchRequestId = useRef(0)

  const loadRecent = useCallback(async () => {
    try {
      setRecentProducts(await applicationServices.diary.getRecentProducts())
    } catch (loadError) {
      console.error('Failed to load recent products.', loadError)
      setError('Не удалось загрузить недавние продукты.')
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadRecent()
  }, [loadRecent])

  useEffect(() => {
    const requestId = ++searchRequestId.current

    if (query.trim() === '') {
      setSearchProducts([])
      return
    }

    async function search(): Promise<void> {
      setIsLoading(true)
      setError(undefined)

      try {
        const products = await applicationServices.diary.searchProducts(query)

        if (requestId === searchRequestId.current) {
          setSearchProducts(products)
        }
      } catch (searchError) {
        console.error('Failed to search products for diary.', searchError)

        if (requestId === searchRequestId.current) {
          setError('Не удалось найти продукты. Попробуйте ещё раз.')
        }
      } finally {
        if (requestId === searchRequestId.current) {
          setIsLoading(false)
        }
      }
    }

    void search()
  }, [query])

  const preview = useMemo(() => {
    if (selectedProduct === undefined || unit === '' || !isPositiveDecimal(amount)) {
      return undefined
    }

    try {
      return applicationServices.diary.previewProduct(selectedProduct, Number(amount), unit)
    } catch {
      return undefined
    }
  }, [amount, selectedProduct, unit])

  function chooseProduct(product: DiaryProduct): void {
    const [defaultUnit] = getDiaryUnitOptions(product.currentVersion)
    setSelectedProduct(product)
    setUnit(defaultUnit.value)
    setAmount(String(product.currentVersion.baseAmount))
    setError(undefined)
  }

  async function addProduct(): Promise<void> {
    if (selectedProduct === undefined || preview === undefined) {
      return
    }

    setIsSaving(true)
    setError(undefined)

    try {
      await applicationServices.diary.addProduct({
        date,
        mealType,
        productId: selectedProduct.product.id,
        amount: Number(amount),
        unit,
      })
      onAdded()
    } catch (addError) {
      console.error('Failed to add diary product.', addError)
      setError('Не удалось добавить продукт. Проверьте количество и попробуйте ещё раз.')
      setIsSaving(false)
    }
  }

  const products = query.trim() === '' ? recentProducts : searchProducts

  return (
    <div className="diary-sheet-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="diary-sheet" role="dialog" aria-modal="true" aria-labelledby="food-picker-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="diary-sheet__handle" aria-hidden="true" />
        {selectedProduct === undefined ? (
          <>
            <div className="diary-sheet__header">
              <div>
                <h2 id="food-picker-title">Добавить в {getMealTypeLabel(mealType).toLowerCase()}</h2>
                <p>Выберите продукт из вашей базы.</p>
              </div>
              <button className="icon-button" type="button" aria-label="Закрыть" onClick={onClose}>×</button>
            </div>
            <label className="search-field">
              <span className="sr-only">Поиск продуктов</span>
              <input autoFocus type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Поиск продуктов" />
            </label>
            {query.trim() === '' ? <h3 className="diary-sheet__section-title">Недавние</h3> : <h3 className="diary-sheet__section-title">Результаты поиска</h3>}
            {isLoading ? <p className="status-message">Загрузка…</p> : null}
            {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
            {!isLoading && error === undefined && products.length === 0 ? <p className="form-empty">{query.trim() === '' ? 'Недавних продуктов пока нет.' : 'Ничего не найдено.'}</p> : null}
            <ul className="food-picker-list">
              {products.map((product) => (
                <li key={product.product.id}>
                  <button type="button" onClick={() => chooseProduct(product)}>
                    <strong>{product.product.name}</strong>
                    <span>{formatNutrition(product.currentVersion)} · v{product.currentVersion.versionNumber}</span>
                  </button>
                </li>
              ))}
            </ul>
          </>
        ) : (
          <>
            <div className="diary-sheet__header">
              <div>
                <button className="back-link" type="button" onClick={() => setSelectedProduct(undefined)}>‹ К продуктам</button>
                <h2 id="food-picker-title">{selectedProduct.product.name}</h2>
                <p>{formatNutrition(selectedProduct.currentVersion)} · v{selectedProduct.currentVersion.versionNumber}</p>
              </div>
              <button className="icon-button" type="button" aria-label="Закрыть" onClick={onClose}>×</button>
            </div>
            <div className="form-field">
              <label htmlFor="diary-unit">Единица</label>
              <select id="diary-unit" value={unit} onChange={(event) => setUnit(event.target.value)}>
                {getDiaryUnitOptions(selectedProduct.currentVersion).map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
              </select>
            </div>
            <div className="form-field">
              <label htmlFor="diary-amount">Количество</label>
              <input id="diary-amount" type="number" inputMode="decimal" min="0" step="any" value={amount} onChange={(event) => setAmount(event.target.value)} />
              {!isPositiveDecimal(amount) && amount !== '' ? <span className="field-error">Количество должно быть больше нуля.</span> : null}
            </div>
            <NutritionPreview nutrition={preview} />
            {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
            <div className="diary-sheet__actions">
              <button className="button button--secondary" type="button" onClick={() => setSelectedProduct(undefined)}>Назад</button>
              <button className="button button--primary" type="button" disabled={preview === undefined || isSaving} onClick={() => void addProduct()}>{isSaving ? 'Добавление…' : 'Добавить'}</button>
            </div>
          </>
        )}
      </section>
    </div>
  )
}

function NutritionPreview({ nutrition }: { nutrition: { calories: number; protein: number; fat: number; carbs: number } | undefined }) {
  if (nutrition === undefined) {
    return <p className="nutrition-preview nutrition-preview--empty">Укажите количество, чтобы увидеть КБЖУ.</p>
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
