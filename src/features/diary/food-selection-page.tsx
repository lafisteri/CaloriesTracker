import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'

import type { DiaryFoodSource } from '@/application/diary/diary-service'
import { applicationServices } from '@/app/providers/application-services'
import { ProductSearchField } from '@/features/products/product-search-field'

import {
  getDiaryAddAmountPath,
  getDiaryAddContext,
  getDiaryAddSelectionPath,
  getDiaryPath,
} from './diary-add-routes'
import { FoodSourceList } from './food-source-list'

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
  const [sources, setSources] = useState<DiaryFoodSource[]>([])
  const [isLoadingProducts, setIsLoadingProducts] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const searchRequestId = useRef(0)

  const loadProducts = useCallback(async (searchQuery: string) => {
    const requestId = ++searchRequestId.current
    setIsLoadingProducts(true)

    try {
      const foundSources = await applicationServices.diary.searchFoodSources(searchQuery)

      if (requestId === searchRequestId.current) {
        setSources(foundSources)
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
    void loadProducts(query)
  }, [loadProducts, query])

  if (context === undefined) {
    return <InvalidDiaryAddContext />
  }

  const addContext = context
  const isSearching = query.trim() !== ''
  const isInitialLoading = !isSearching && isLoadingProducts
  const isEmptyDatabase = !isSearching && !isLoadingProducts && sources.length === 0
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

  function selectSource(source: DiaryFoodSource): void {
    const sourceId = source.sourceType === 'product' ? source.product.id : source.recipe.id
    navigate(getDiaryAddAmountPath(addContext, source.sourceType, sourceId), { state: { diaryAddSelectionInHistory: true } })
  }

  function retryLoading(): void {
    setError(undefined)
    void loadProducts(query)
  }

  return (
    <section className="diary-add-page diary-add-page--with-bottom-navigation" aria-labelledby="food-selection-title">
      <header className="diary-add-page__header">
        <button className="back-link diary-add-page__back" type="button" onClick={returnToDiary}>
          ‹ Дневник
        </button>
      </header>
      <div className="diary-add-page__scroll">
        <div className="diary-add-page__intro">
          <h1 id="food-selection-title">Продукты</h1>
        </div>
        <div className="quick-actions">
          <Link className="button button--secondary" to={`${selectionPath}/scan`} state={{ scannerInHistory: true }}>Сканировать</Link>
          <Link className="button button--primary" to={createProductPath}>Добавить</Link>
        </div>
        <ProductSearchField value={query} onChange={setQuery} placeholder="Поиск продукта или блюда..." label="Поиск по продуктам и блюдам" />
        {isInitialLoading ? <p className="status-message">Загрузка…</p> : null}
        {error === undefined ? null : (
          <div className="status-message status-message--error" role="alert">
            <p>{error}</p>
            <button className="button button--secondary" type="button" onClick={retryLoading}>Повторить</button>
          </div>
        )}
        {error !== undefined || isInitialLoading ? null : isEmptyDatabase ? (
          <section className="empty-state diary-add-page__empty" aria-labelledby="empty-product-database-title">
            <h2 id="empty-product-database-title">В базе пока нет продуктов</h2>
            <p>Создайте первый продукт с помощью кнопки выше, чтобы добавить его в дневник.</p>
          </section>
        ) : (
          <div className="diary-selection-sections">
            <section aria-labelledby="database-products-title">
              <h2 id="database-products-title">{isSearching ? 'Результаты поиска' : 'Моя база'}</h2>
              {sources.length === 0 ? (
                <div className="form-empty">
                  <p>Ничего не найдено. Измените запрос или создайте продукт.</p>
                </div>
              ) : <FoodSourceList sources={sources} onSelect={selectSource} />}
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
      <Link className="button button--secondary" to="/">К дневнику</Link>
    </section>
  )
}
