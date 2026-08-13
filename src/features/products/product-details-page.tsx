import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'

import type { ProductDetails } from '@/application/products/product-service'
import { applicationServices } from '@/app/providers/application-services'
import { formatBaseAmount, formatConversionUnit, formatNutrition, formatNumber } from '@/features/products/product-formatters'

export function ProductDetailsPage() {
  const { productId } = useParams()
  const navigate = useNavigate()
  const [details, setDetails] = useState<ProductDetails | undefined>()
  const [selectedVersionId, setSelectedVersionId] = useState<string | undefined>()
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const [deleteError, setDeleteError] = useState<string | undefined>()
  const [isDeleting, setIsDeleting] = useState(false)

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
        const product = await applicationServices.products.getById(productId)

        if (isMounted) {
          setDetails(product)
          setSelectedVersionId(product?.currentVersion.id)
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

  const selectedVersion = details.versions.find((version) => version.id === selectedVersionId) ?? details.currentVersion
  const isCurrentVersion = selectedVersion.id === details.currentVersion.id
  const product = details.product

  async function deleteProduct(): Promise<void> {
    if (!window.confirm(`Удалить продукт «${product.name}»? Его история версий сохранится.`)) {
      return
    }

    setIsDeleting(true)
    setDeleteError(undefined)

    try {
      await applicationServices.products.softDelete(product.id)
      navigate('/products', { replace: true })
    } catch (deleteProductError) {
      console.error('Failed to delete product.', deleteProductError)
      setDeleteError('Не удалось удалить продукт. Попробуйте ещё раз.')
      setIsDeleting(false)
    }
  }

  return (
    <section className="product-details" aria-labelledby="product-title">
      <Link className="back-link" to="/products">‹ Все продукты</Link>
      <div className="page-heading">
        <div>
          <h1 id="product-title">{details.product.name}</h1>
          {details.product.barcode === undefined ? null : <p>Штрихкод: {details.product.barcode}</p>}
        </div>
        <div className="product-details__actions">
          <Link className="button button--primary" to={`/products/${productId}/edit`}>Изменить</Link>
          <button className="button button--danger" type="button" disabled={isDeleting} onClick={() => void deleteProduct()}>
            {isDeleting ? 'Удаление…' : 'Удалить'}
          </button>
        </div>
      </div>

      {deleteError === undefined ? null : <p className="form-submit-error" role="alert">{deleteError}</p>}

      <section className="product-card" aria-labelledby="current-version-title">
        <div className="section-heading">
          <h2 id="current-version-title">{isCurrentVersion ? 'Текущая версия' : `Версия v${selectedVersion.versionNumber}`}</h2>
          <span className="version-badge">v{selectedVersion.versionNumber}</span>
        </div>
        <p className="product-card__base">На {formatBaseAmount(selectedVersion)}</p>
        <p className="product-card__calories">{formatNumber(selectedVersion.calories)} <span>ккал</span></p>
        <dl className="nutrition-grid">
          <div><dt>Белки</dt><dd>{formatNumber(selectedVersion.protein)} г</dd></div>
          <div><dt>Жиры</dt><dd>{formatNumber(selectedVersion.fat)} г</dd></div>
          <div><dt>Углеводы</dt><dd>{formatNumber(selectedVersion.carbs)} г</dd></div>
        </dl>
        {selectedVersion.servingUnits.length === 0 ? null : (
          <div className="serving-units">
            <h3>Дополнительные единицы</h3>
            <ul>
              {selectedVersion.servingUnits.map((unit) => (
                <li key={unit.id}>1 {unit.name} = {formatNumber(unit.conversionAmount)} {formatConversionUnit(unit.conversionUnit)}</li>
              ))}
            </ul>
          </div>
        )}
      </section>

      <section className="version-history" aria-labelledby="version-history-title">
        <h2 id="version-history-title">История версий</h2>
        <ol>
          {[...details.versions].reverse().map((version) => (
            <li key={version.id} className={version.id === selectedVersion.id ? 'version-history__item version-history__item--selected' : 'version-history__item'}>
              <button className="version-history__button" type="button" onClick={() => setSelectedVersionId(version.id)}>
                <span><strong>v{version.versionNumber}</strong><em>{version.id === details.currentVersion.id ? 'Текущая' : new Date(version.createdAt).toLocaleDateString('ru-RU')}</em></span>
                <p>{formatNutrition(version)} · на {formatBaseAmount(version)}</p>
              </button>
            </li>
          ))}
        </ol>
      </section>
    </section>
  )
}
