import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'

import type { ProductListItem } from '@/application/products/product-service'
import { applicationServices } from '@/app/providers/application-services'
import { formatBaseAmount, formatNutrition } from '@/features/products/product-formatters'

export function ProductsPage() {
  const [query, setQuery] = useState('')
  const [catalogTab, setCatalogTab] = useState<'products' | 'recipes'>('products')
  const [products, setProducts] = useState<ProductListItem[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const searchRequestId = useRef(0)

  const loadProducts = useCallback(async (searchQuery: string) => {
    const requestId = ++searchRequestId.current
    setIsLoading(true)
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
        setIsLoading(false)
      }
    }
  }, [])

  useEffect(() => {
    if (catalogTab === 'products') {
      void loadProducts(query)
    }
  }, [catalogTab, loadProducts, query])

  return (
    <section className="products-page" aria-labelledby="products-title">
      <div className="page-heading">
        <div>
          <h1 id="products-title">Продукты</h1>
          <p>Ваша личная база продуктов.</p>
        </div>
        {catalogTab === 'products' ? <Link className="button button--primary" to="/products/new">Добавить</Link> : null}
      </div>

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

      {catalogTab === 'recipes' ? (
        <section id="recipes-panel" className="empty-state" role="tabpanel" aria-labelledby="recipes-tab">
          <h2>Рецепты появятся позже</h2>
          <p>Этот раздел будет реализован в отдельной фазе. Продукты уже можно создавать и редактировать.</p>
        </section>
      ) : null}

      {catalogTab === 'products' ? <label id="products-panel" className="search-field" role="tabpanel" aria-labelledby="products-tab">
        <span className="sr-only">Поиск продуктов</span>
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Поиск по названию или штрихкоду"
        />
      </label> : null}

      {catalogTab === 'products' && isLoading ? <p className="status-message">Загрузка…</p> : null}
      {catalogTab === 'products' && error !== undefined ? (
        <div className="status-message status-message--error" role="alert">
          <p>{error}</p>
          <button className="button button--secondary" type="button" onClick={() => void loadProducts(query)}>Повторить</button>
        </div>
      ) : null}

      {catalogTab === 'products' && !isLoading && error === undefined && products.length === 0 ? (
        <div className="empty-state">
          <h2>{query.trim() === '' ? 'Продуктов пока нет' : 'Ничего не найдено'}</h2>
          <p>{query.trim() === '' ? 'Добавьте первый продукт — всё будет сохранено на этом устройстве.' : 'Измените запрос или добавьте новый продукт.'}</p>
          {query.trim() === '' ? <Link className="button button--primary" to="/products/new">Создать продукт</Link> : null}
        </div>
      ) : null}

      {catalogTab === 'products' && !isLoading && error === undefined && products.length > 0 ? (
        <ul className="product-list">
          {products.map(({ product, currentVersion }) => (
            <li key={product.id}>
              <Link className="product-list__item" to={`/products/${product.id}`}>
                <span className="product-list__name">{product.name}</span>
                <span className="product-list__details">
                  {formatNutrition(currentVersion)} · на {formatBaseAmount(currentVersion)}
                </span>
                {product.barcode === undefined ? null : <span className="product-list__barcode">Штрихкод: {product.barcode}</span>}
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  )
}
