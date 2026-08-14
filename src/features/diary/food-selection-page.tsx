import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'

import type { DiaryProduct } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'
import { ProductList } from '@/features/products/product-list'
import { ProductSearchField } from '@/features/products/product-search-field'

import {
  getDiaryAddAmountPath,
  getDiaryAddContext,
  getDiaryAddSelectionPath,
  getDiaryPath,
} from './diary-add-routes'
import { formatDiaryShortDate, getMealTypeLabel } from './diary-formatters'

interface DiaryAddNavigationState {
  diaryAddFromDiary?: boolean
}

/** Full-screen selection mode for choosing a current ProductVersion for a Diary entry. */
export function FoodSelectionPage() {
  const { date, mealType } = useParams()
  const context = getDiaryAddContext(date, mealType)
  const navigate = useNavigate()
  const location = useLocation()
  const [query, setQuery] = useState('')
  const [recentProducts, setRecentProducts] = useState<DiaryProduct[]>([])
  const [products, setProducts] = useState<DiaryProduct[]>([])
  const [isLoadingRecent, setIsLoadingRecent] = useState(true)
  const [isLoadingProducts, setIsLoadingProducts] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const searchRequestId = useRef(0)

  const loadRecent = useCallback(async () => {
    setIsLoadingRecent(true)

    try {
      setRecentProducts(await applicationServices.diary.getRecentProducts())
    } catch (loadError) {
      console.error('Failed to load recent diary products.', loadError)
      setError('Не удалось загрузить продукты. Попробуйте ещё раз.')
    } finally {
      setIsLoadingRecent(false)
    }
  }, [])

  const loadProducts = useCallback(async (searchQuery: string) => {
    const requestId = ++searchRequestId.current
    setIsLoadingProducts(true)

    try {
      const foundProducts = await applicationServices.diary.searchProducts(searchQuery)

      if (requestId === searchRequestId.current) {
        setProducts(foundProducts)
      }
    } catch (loadError) {
      console.error('Failed to search products for diary.', loadError)

      if (requestId === searchRequestId.current) {
        setError('Не удалось найти продукты. Попробуйте ещё раз.')
      }
    } finally {
      if (requestId === searchRequestId.current) {
        setIsLoadingProducts(false)
      }
    }
  }, [])

  useEffect(() => {
    void loadRecent()
  }, [loadRecent])

  useEffect(() => {
    void loadProducts(query)
  }, [loadProducts, query])

  if (context === undefined) {
    return <InvalidDiaryAddContext />
  }

  const addContext = context
  const isSearching = query.trim() !== ''
  const isLoading = isLoadingRecent || isLoadingProducts
  const isEmptyDatabase = !isSearching && !isLoadingProducts && products.length === 0
  const selectionPath = getDiaryAddSelectionPath(addContext)
  const createProductPath = `/products/new?returnTo=${encodeURIComponent(selectionPath)}`
  const state = location.state as DiaryAddNavigationState | null

  function returnToDiary(): void {
    if (state?.diaryAddFromDiary === true) {
      navigate(-1)
      return
    }

    navigate(getDiaryPath(addContext.date), { replace: true })
  }

  function selectProduct(product: DiaryProduct): void {
    navigate(getDiaryAddAmountPath(addContext, product.product.id), { state: { diaryAddSelectionInHistory: true } })
  }

  function retryLoading(): void {
    setError(undefined)
    void loadRecent()
    void loadProducts(query)
  }

  return (
    <section className="diary-add-page" aria-labelledby="food-selection-title">
      <header className="diary-add-page__header">
        <button className="back-link diary-add-page__back" type="button" onClick={returnToDiary}>
          ‹ Добавить в {getMealTypeLabel(addContext.mealType).toLocaleLowerCase()}
        </button>
        <span>{formatDiaryShortDate(addContext.date)}</span>
      </header>
      <div className="diary-add-page__scroll">
        <div className="diary-add-page__intro">
          <h1 id="food-selection-title">Выберите продукт</h1>
          <p>Добавление в {getMealTypeLabel(addContext.mealType).toLocaleLowerCase()}.</p>
        </div>
        <ProductSearchField value={query} onChange={setQuery} placeholder="Поиск продукта..." autoFocus />
        {isLoading ? <p className="status-message">Загрузка…</p> : null}
        {error === undefined ? null : (
          <div className="status-message status-message--error" role="alert">
            <p>{error}</p>
            <button className="button button--secondary" type="button" onClick={retryLoading}>Повторить</button>
          </div>
        )}
        {error !== undefined || isLoading ? null : isEmptyDatabase ? (
          <section className="empty-state diary-add-page__empty" aria-labelledby="empty-product-database-title">
            <h2 id="empty-product-database-title">В базе пока нет продуктов</h2>
            <p>Создайте первый продукт, чтобы добавить его в дневник.</p>
            <Link className="button button--primary" to={createProductPath}>Создать продукт</Link>
          </section>
        ) : (
          <div className="diary-selection-sections">
            {!isSearching ? (
              <section aria-labelledby="recent-products-title">
                <h2 id="recent-products-title">Недавние</h2>
                {recentProducts.length === 0 ? <p className="diary-selection-sections__empty">Недавних продуктов пока нет</p> : <ProductList products={recentProducts} onSelect={selectProduct} />}
              </section>
            ) : null}
            <section aria-labelledby="database-products-title">
              <div className="diary-selection-sections__heading">
                <h2 id="database-products-title">{isSearching ? 'Результаты поиска' : 'Моя база'}</h2>
                {!isSearching ? <Link to={createProductPath}>+ Создать продукт</Link> : null}
              </div>
              {products.length === 0 ? (
                <div className="form-empty">
                  <p>Ничего не найдено.</p>
                  <Link to={createProductPath}>Создать продукт</Link>
                </div>
              ) : <ProductList products={products} onSelect={selectProduct} />}
            </section>
          </div>
        )}
      </div>
    </section>
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
