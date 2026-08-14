import { Link } from 'react-router-dom'

import type { ProductListItem } from '@/application/products/product-service'

import { formatBaseAmount, formatNutrition } from './product-formatters'

interface ProductListProps {
  products: ProductListItem[]
  onSelect?: (product: ProductListItem) => void
}

/** Presents a Product's current version in either management or selection mode. */
export function ProductList({ products, onSelect }: ProductListProps) {
  return (
    <ul className="product-list">
      {products.map((item) => (
        <li key={item.product.id}>
          {onSelect === undefined ? (
            <Link className="product-list__item" to={`/products/${item.product.id}`}>
              <ProductListRow item={item} />
            </Link>
          ) : (
            <button className="product-list__item product-list__item--selectable" type="button" onClick={() => onSelect(item)}>
              <ProductListRow item={item} />
            </button>
          )}
        </li>
      ))}
    </ul>
  )
}

export function ProductListRow({ item }: { item: ProductListItem }) {
  const { product, currentVersion } = item

  return (
    <>
      <span className="product-list__name">{product.name}</span>
      <span className="product-list__details">
        {formatNutrition(currentVersion)} · на {formatBaseAmount(currentVersion)}
      </span>
      {product.barcode === undefined ? null : <span className="product-list__barcode">Штрихкод: {product.barcode}</span>}
    </>
  )
}
