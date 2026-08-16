import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useLocation } from 'react-router-dom'

import type { ProductListItem } from '@/application/products/product-service'
import type { RecipeListItem } from '@/application/recipes/recipe-service'
import { applicationServices } from '@/app/providers/application-services'
import { RecipeList } from '@/features/recipes/recipe-list'

import { ProductList } from './product-list'
import { ProductSearchField } from './product-search-field'

export function ProductsPage() {
  const location = useLocation()
  const [query, setQuery] = useState('')
  const [catalogTab, setCatalogTab] = useState<'products' | 'recipes'>(() => new URLSearchParams(location.search).get('tab') === 'recipes' ? 'recipes' : 'products')
  const [products, setProducts] = useState<ProductListItem[]>([])
  const [recipes, setRecipes] = useState<RecipeListItem[]>([])
  const [hasLoadedProducts, setHasLoadedProducts] = useState(false)
  const [hasLoadedRecipes, setHasLoadedRecipes] = useState(false)
  const [error, setError] = useState<string | undefined>()
  const searchRequestId = useRef(0)

  const loadProducts = useCallback(async (searchQuery: string) => {
    const requestId = ++searchRequestId.current
    setError(undefined)

    try {
      const foundProducts = await applicationServices.products.search(searchQuery)

      if (requestId === searchRequestId.current) {
        setProducts(foundProducts)
      }
    } catch (loadError) {
      console.error('Failed to load products.', loadError)

      if (requestId === searchRequestId.current) {
        setError('Не удалось загрузить продукты. Попробуйте ещё раз.')
      }
    } finally {
      if (requestId === searchRequestId.current) {
        setHasLoadedProducts(true)
      }
    }
  }, [])

  const loadRecipes = useCallback(async (searchQuery: string) => {
    const requestId = ++searchRequestId.current
    setError(undefined)

    try {
      const foundRecipes = await applicationServices.recipes.search(searchQuery)

      if (requestId === searchRequestId.current) {
        setRecipes(foundRecipes)
      }
    } catch (loadError) {
      console.error('Failed to load recipes.', loadError)

      if (requestId === searchRequestId.current) {
        setError('Не удалось загрузить рецепты. Попробуйте ещё раз.')
      }
    } finally {
      if (requestId === searchRequestId.current) {
        setHasLoadedRecipes(true)
      }
    }
  }, [])

  useEffect(() => {
    void (catalogTab === 'products' ? loadProducts(query) : loadRecipes(query))
  }, [catalogTab, loadProducts, loadRecipes, query])

  const isInitialLoading = catalogTab === 'products' ? !hasLoadedProducts : !hasLoadedRecipes

  return (
    <section className="products-page" aria-label="Каталог продуктов и рецептов">
      <div className="catalog-tabs" role="tablist" aria-label="Каталог">
        <button
          className={catalogTab === 'products' ? 'catalog-tabs__tab catalog-tabs__tab--active' : 'catalog-tabs__tab'}
          id="products-tab"
          role="tab"
          type="button"
          aria-selected={catalogTab === 'products'}
          aria-controls="products-panel"
          onClick={() => setCatalogTab('products')}
        >
          Продукты
        </button>
        <button
          className={catalogTab === 'recipes' ? 'catalog-tabs__tab catalog-tabs__tab--active' : 'catalog-tabs__tab'}
          id="recipes-tab"
          role="tab"
          type="button"
          aria-selected={catalogTab === 'recipes'}
          aria-controls="recipes-panel"
          onClick={() => setCatalogTab('recipes')}
        >
          Рецепты
        </button>
      </div>

      <div className={catalogTab === 'products' ? 'quick-actions' : 'quick-actions quick-actions--single'}>
        {catalogTab === 'products' ? (
          <>
            <Link className="button button--secondary" to="/products/scan" state={{ scannerInHistory: true }}>Сканировать</Link>
            <Link className="button button--primary" to="/products/new">Добавить</Link>
          </>
        ) : <Link className="button button--primary" to="/recipes/new">Создать рецепт</Link>}
      </div>

      <div id={catalogTab === 'products' ? 'products-panel' : 'recipes-panel'} role="tabpanel" aria-labelledby={catalogTab === 'products' ? 'products-tab' : 'recipes-tab'}>
          <ProductSearchField
            value={query}
            onChange={setQuery}
            placeholder={catalogTab === 'products' ? 'Поиск по названию или штрихкоду' : 'Поиск рецептов'}
            label={catalogTab === 'products' ? 'Поиск продуктов' : 'Поиск рецептов'}
          />
      </div>

      {isInitialLoading ? <p className="status-message">Загрузка…</p> : null}
      {error !== undefined ? (
        <div className="status-message status-message--error" role="alert">
          <p>{error}</p>
          <button className="button button--secondary" type="button" onClick={() => void (catalogTab === 'products' ? loadProducts(query) : loadRecipes(query))}>Повторить</button>
        </div>
      ) : null}

      {catalogTab === 'products' && !isInitialLoading && error === undefined && products.length === 0 ? (
        <div className="empty-state">
          <h2>{query.trim() === '' ? 'Продуктов пока нет' : 'Ничего не найдено'}</h2>
          <p>{query.trim() === '' ? 'Добавьте первый продукт с помощью кнопки выше.' : 'Измените запрос или добавьте новый продукт.'}</p>
        </div>
      ) : null}

      {catalogTab === 'products' && !isInitialLoading && error === undefined && products.length > 0 ? <ProductList products={products} /> : null}
      {catalogTab === 'recipes' && !isInitialLoading && error === undefined && recipes.length === 0 ? (
        <div className="empty-state">
          <h2>{query.trim() === '' ? 'У вас пока нет рецептов' : 'Ничего не найдено'}</h2>
          <p>{query.trim() === '' ? 'Создайте первый рецепт с помощью кнопки выше.' : 'Измените запрос или создайте новый рецепт.'}</p>
        </div>
      ) : null}
      {catalogTab === 'recipes' && !isInitialLoading && error === undefined && recipes.length > 0 ? <RecipeList recipes={recipes} /> : null}
    </section>
  )
}
