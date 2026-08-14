import { Link } from 'react-router-dom'

import type { RecipeListItem } from '@/application/recipes/recipe-service'

import { formatRecipeNutrition, getRecipePrimaryNutrition, toNutrition } from './recipe-formatters'

export function RecipeList({ recipes }: { recipes: RecipeListItem[] }) {
  return (
    <ul className="product-list recipe-list">
      {recipes.map(({ recipe, currentVersion }) => (
        <li key={recipe.id}>
          <Link className="product-list__item" to={`/recipes/${recipe.id}`}>
            <span className="product-list__name">{recipe.name}</span>
            <span className="product-list__details">{getRecipePrimaryNutrition(currentVersion)}</span>
            <span className="product-list__details">{formatRecipeNutrition(toNutrition(currentVersion))}</span>
            <span className="food-source-list__type">Блюдо · v{currentVersion.versionNumber}</span>
          </Link>
        </li>
      ))}
    </ul>
  )
}
