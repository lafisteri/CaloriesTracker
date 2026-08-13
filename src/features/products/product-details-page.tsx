import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'

import { productService, type ProductDetails } from '@/application/products/product-service'
import { formatBaseAmount, formatNutrition, formatNumber } from '@/features/products/product-formatters'

export function ProductDetailsPage() {
  const { productId } = useParams()
  const [details, setDetails] = useState<ProductDetails | undefined>()
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()

  useEffect(() => {
    let isMounted = true

    async function loadProduct(): Promise<void> {
      if (productId === undefined) {
        setIsLoading(false)
        return
      }

      setIsLoading(true)
      setError(undefined)

      try {
        const product = await productService.getById(productId)

        if (isMounted) {
          setDetails(product)
        }
      } catch (loadError) {
        console.error('Failed to load product.', loadError)

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

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  if (error !== undefined) {
    return <p className="status-message status-message--error" role="alert">{error}</p>
  }

  if (details === undefined || productId === undefined) {
    return (
      <section className="empty-state" aria-labelledby="product-missing-title">
        <h1 id="product-missing-title">Продукт не найден</h1>
        <p>Возможно, он был удалён или ссылка устарела.</p>
        <Link className="button button--secondary" to="/products">К продуктам</Link>
      </section>
    )
  }

  return (
    <section className="product-details" aria-labelledby="product-title">
      <Link className="back-link" to="/products">‹ Все продукты</Link>
      <div className="page-heading">
        <div>
          <h1 id="product-title">{details.product.name}</h1>
          {details.product.barcode === undefined ? null : <p>Штрихкод: {details.product.barcode}</p>}
        </div>
        <Link className="button button--primary" to={`/products/${productId}/edit`}>Изменить</Link>
      </div>

      <section className="product-card" aria-labelledby="current-version-title">
        <div className="section-heading">
          <h2 id="current-version-title">Текущая версия</h2>
          <span className="version-badge">v{details.currentVersion.versionNumber}</span>
        </div>
        <p className="product-card__base">На {formatBaseAmount(details.currentVersion)}</p>
        <p className="product-card__calories">{formatNumber(details.currentVersion.calories)} <span>ккал</span></p>
        <dl className="nutrition-grid">
          <div><dt>Белки</dt><dd>{formatNumber(details.currentVersion.protein)} г</dd></div>
          <div><dt>Жиры</dt><dd>{formatNumber(details.currentVersion.fat)} г</dd></div>
          <div><dt>Углеводы</dt><dd>{formatNumber(details.currentVersion.carbs)} г</dd></div>
        </dl>
        {details.currentVersion.servingUnits.length === 0 ? null : (
          <div className="serving-units">
            <h3>Дополнительные единицы</h3>
            <ul>
              {details.currentVersion.servingUnits.map((unit) => (
                <li key={unit.id}>1 {unit.name} = {formatNumber(unit.conversionAmount)} {unit.conversionUnit}</li>
              ))}
            </ul>
          </div>
        )}
      </section>

      <section className="version-history" aria-labelledby="version-history-title">
        <h2 id="version-history-title">История версий</h2>
        <ol>
          {[...details.versions].reverse().map((version) => (
            <li key={version.id} className={version.id === details.currentVersion.id ? 'version-history__item version-history__item--current' : 'version-history__item'}>
              <div><strong>v{version.versionNumber}</strong><span>{version.id === details.currentVersion.id ? 'Текущая' : new Date(version.createdAt).toLocaleDateString('ru-RU')}</span></div>
              <p>{formatNutrition(version)} · на {formatBaseAmount(version)}</p>
            </li>
          ))}
        </ol>
      </section>
    </section>
  )
}
