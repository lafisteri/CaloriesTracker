import type { DiaryFoodSource } from '@/application/diary/diary-service'
import { ProductListRow } from '@/features/products/product-list'
import { getRecipePrimaryMacros, getRecipePrimaryNutrition } from '@/features/recipes/recipe-formatters'

interface FoodSourceListProps {
  sources: DiaryFoodSource[]
  onSelect: (source: DiaryFoodSource) => void
}

/** Shared Diary selection rows for the two snapshot-capable food sources. */
export function FoodSourceList({ sources, onSelect }: FoodSourceListProps) {
  return (
    <ul className="product-list food-source-list">
      {sources.map((source) => (
        <li key={`${source.sourceType}:${source.sourceType === 'product' ? source.product.id : source.recipe.id}`}>
          <button className="product-list__item product-list__item--selectable" type="button" onClick={() => onSelect(source)}>
            {source.sourceType === 'product' ? (
              <>
                <ProductListRow item={source} />
                <span className="food-source-list__type">Продукт</span>
              </>
            ) : (
              <>
                <span className="product-list__name">{source.recipe.name}</span>
                <span className="product-list__details">{getRecipePrimaryNutrition(source.currentVersion)}</span>
                <span className="product-list__macros">{getRecipePrimaryMacros(source.currentVersion)}</span>
                <span className="food-source-list__type">Блюдо · v{source.currentVersion.versionNumber}</span>
              </>
            )}
          </button>
        </li>
      ))}
    </ul>
  )
}
