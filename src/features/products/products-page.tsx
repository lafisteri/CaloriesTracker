import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'

import { productService, type ProductListItem } from '@/application/products/product-service'
import { formatBaseAmount, formatNutrition } from '@/features/products/product-formatters'

export function ProductsPage() {
  const [query, setQuery] = useState('')
  const [products, setProducts] = useState<ProductListItem[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()

  const loadProducts = useCallback(async (searchQuery: string) => {
    setIsLoading(true)
    setError(undefined)

    try {
      setProducts(await productService.search(searchQuery))
    } catch (loadError) {
      console.error('Failed to load products.', loadError)
      setError('Не удалось загрузить продукты. Попробуйте ещё раз.')
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadProducts(query)
  }, [loadProducts, query])

  return (
    <section className="products-page" aria-labelledby="products-title">
      <div className="page-heading">
        <div>
          <h1 id="products-title">Продукты</h1>
          <p>Ваша личная база продуктов.</p>
        </div>
        <Link className="button button--primary" to="/products/new">Добавить</Link>
      </div>

      <label className="search-field">
        <span className="sr-only">Поиск продуктов</span>
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Поиск по названию или штрихкоду"
        />
      </label>

      {isLoading ? <p className="status-message">Загрузка…</p> : null}
      {error === undefined ? null : (
        <div className="status-message status-message--error" role="alert">
          <p>{error}</p>
          <button className="button button--secondary" type="button" onClick={() => void loadProducts(query)}>Повторить</button>
        </div>
      )}

      {!isLoading && error === undefined && products.length === 0 ? (
        <div className="empty-state">
          <h2>{query.trim() === '' ? 'Продуктов пока нет' : 'Ничего не найдено'}</h2>
          <p>{query.trim() === '' ? 'Добавьте первый продукт — всё будет сохранено на этом устройстве.' : 'Измените запрос или добавьте новый продукт.'}</p>
          {query.trim() === '' ? <Link className="button button--primary" to="/products/new">Создать продукт</Link> : null}
        </div>
      ) : null}

      {!isLoading && error === undefined && products.length > 0 ? (
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
