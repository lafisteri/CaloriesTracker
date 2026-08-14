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
import { formatDiaryShortDate, getMealTypeLabel } from './diary-formatters'
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
  const [recentSources, setRecentSources] = useState<DiaryFoodSource[]>([])
  const [sources, setSources] = useState<DiaryFoodSource[]>([])
  const [isLoadingRecent, setIsLoadingRecent] = useState(true)
  const [isLoadingProducts, setIsLoadingProducts] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const searchRequestId = useRef(0)

  const loadRecent = useCallback(async () => {
    setIsLoadingRecent(true)

    try {
      setRecentSources(await applicationServices.diary.getRecentFoodSources(6))
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
  const isInitialLoading = !isSearching && (isLoadingRecent || isLoadingProducts)
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
    void loadRecent()
    void loadProducts(query)
  }

  return (
    <section className="diary-add-page" aria-labelledby="food-selection-title">
      <header className="diary-add-page__header">
        <button className="back-link diary-add-page__back" type="button" onClick={returnToDiary}>
          ‹ Дневник
        </button>
        <span>{formatDiaryShortDate(addContext.date)}</span>
      </header>
      <div className="diary-add-page__scroll">
        <div className="diary-add-page__intro">
          <h1 id="food-selection-title">Выберите еду</h1>
          <p>Добавление в {getMealTypeLabel(addContext.mealType).toLocaleLowerCase()}.</p>
        </div>
        <ProductSearchField value={query} onChange={setQuery} placeholder="Поиск еды..." label="Поиск по продуктам и блюдам" />
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
            <p>Создайте первый продукт, чтобы добавить его в дневник.</p>
            <Link className="button button--primary" to={createProductPath}>Создать продукт</Link>
          </section>
        ) : (
          <div className="diary-selection-sections">
            {!isSearching ? (
              <section aria-labelledby="recent-products-title">
                <h2 id="recent-products-title">Недавние</h2>
                {recentSources.length === 0 ? <p className="diary-selection-sections__empty">Недавних продуктов и блюд пока нет</p> : <FoodSourceList className="food-source-list--recent" sources={recentSources} onSelect={selectSource} />}
              </section>
            ) : null}
            <section aria-labelledby="database-products-title">
              <div className="diary-selection-sections__heading">
                <h2 id="database-products-title">{isSearching ? 'Результаты поиска' : 'Моя база'}</h2>
                {!isSearching ? (
                  <span className="diary-selection-sections__actions">
                    <Link to={`${selectionPath}/scan`} state={{ scannerInHistory: true }}>Сканировать</Link>
                    <Link to={createProductPath}>+ Создать продукт</Link>
                  </span>
                ) : null}
              </div>
              {sources.length === 0 ? (
                <div className="form-empty">
                  <p>Ничего не найдено.</p>
                  <Link to={createProductPath}>Создать продукт</Link>
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
      <Link className="button button--secondary" to="/diary">К дневнику</Link>
    </section>
  )
}
