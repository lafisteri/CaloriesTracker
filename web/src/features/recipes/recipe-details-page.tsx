import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'

import type { RecipeDetails, RecipeVersionDetails } from '@/application/recipes/recipe-service'
import { BackLink } from '@/app/layout/back-link'
import { applicationServices } from '@/app/providers/application-services'
import { getDiaryUnitOptions } from '@/domain/diary/diary-unit'
import { formatDiaryNumber } from '@/features/diary/diary-formatters'

import { formatRecipeNutrition, getRecipePrimaryNutrition, toNutrition } from './recipe-formatters'

export function RecipeDetailsPage() {
  const { recipeId } = useParams()
  const navigate = useNavigate()
  const [details, setDetails] = useState<RecipeDetails | undefined>()
  const [selectedVersionId, setSelectedVersionId] = useState<string | undefined>()
  const [selectedVersionDetails, setSelectedVersionDetails] = useState<RecipeVersionDetails | undefined>()
  const [isLoading, setIsLoading] = useState(true)
  const [isDeleting, setIsDeleting] = useState(false)
  const [isUpdatingIngredients, setIsUpdatingIngredients] = useState(false)
  const [error, setError] = useState<string | undefined>()

  useEffect(() => {
    let isMounted = true

    async function loadRecipe(): Promise<void> {
      if (recipeId === undefined) {
        setIsLoading(false)
        return
      }

      try {
        const recipe = await applicationServices.recipes.getById(recipeId)

        if (isMounted) {
          setDetails(recipe)
          setSelectedVersionId(recipe?.currentVersion.id)
          setSelectedVersionDetails(recipe?.currentVersionDetails)
        }
      } catch (loadError) {
        console.error('Failed to load recipe.', loadError)

        if (isMounted) {
          setError('Не удалось загрузить рецепт. Попробуйте ещё раз.')
        }
      } finally {
        if (isMounted) {
          setIsLoading(false)
        }
      }
    }

    void loadRecipe()

    return () => {
      isMounted = false
    }
  }, [recipeId])

  async function selectVersion(versionId: string): Promise<void> {
    if (details === undefined) {
      return
    }

    const version = details.versions.find((candidate) => candidate.id === versionId)

    if (version === undefined) {
      return
    }

    setSelectedVersionId(versionId)
    setSelectedVersionDetails(await applicationServices.recipes.getVersionDetails(version))
  }

  async function updateIngredients(): Promise<void> {
    if (details === undefined) {
      return
    }

    setIsUpdatingIngredients(true)
    setError(undefined)

    try {
      const updated = await applicationServices.recipes.updateIngredients(details.recipe.id)
      setDetails(updated)
      setSelectedVersionId(updated.currentVersion.id)
      setSelectedVersionDetails(updated.currentVersionDetails)
    } catch (updateError) {
      console.error('Failed to update recipe ingredients.', updateError)
      setError('Не удалось обновить ингредиенты.')
    } finally {
      setIsUpdatingIngredients(false)
    }
  }

  async function deleteRecipe(): Promise<void> {
    if (details === undefined) {
      return
    }

    setIsDeleting(true)
    setError(undefined)

    try {
      await applicationServices.recipes.softDelete(details.recipe.id)
      navigate('/products?tab=recipes', { replace: true })
    } catch (deleteError) {
      console.error('Failed to delete recipe.', deleteError)
      setError('Не удалось удалить рецепт.')
      setIsDeleting(false)
    }
  }

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  if (details === undefined || selectedVersionDetails === undefined) {
    return (
      <section className="empty-state" aria-labelledby="recipe-missing-title">
        <h1 id="recipe-missing-title">Рецепт не найден</h1>
        <p>{error ?? 'Возможно, он был удалён или ссылка устарела.'}</p>
        <Link className="button button--secondary" to="/products?tab=recipes">К рецептам</Link>
      </section>
    )
  }

  const selectedVersion = selectedVersionDetails.version
  const isCurrentVersion = selectedVersion.id === details.currentVersion.id
  const updateableIngredientsCount = details.outdatedIngredients.filter((ingredient) => ingredient.canUpdate).length
  const incompatibleIngredientsCount = details.outdatedIngredients.length - updateableIngredientsCount

  return (
    <section className="recipe-details" aria-labelledby="recipe-title">
      <BackLink to="/products?tab=recipes" />
      <div className="page-heading">
        <div>
          <h1 id="recipe-title">{details.recipe.name}</h1>
          <p>{getRecipePrimaryNutrition(selectedVersion)}</p>
        </div>
        <div className="product-details__actions">
          <Link className="button button--primary" to={`/recipes/${details.recipe.id}/edit`}>Изменить</Link>
          <button className="button button--danger" type="button" disabled={isDeleting} onClick={() => void deleteRecipe()}>{isDeleting ? 'Удаление…' : 'Удалить'}</button>
        </div>
      </div>

      {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
      {isCurrentVersion && details.outdatedIngredients.length > 0 ? (
        <section className="recipe-update-notice" aria-labelledby="recipe-updates-title">
          <div>
            <h2 id="recipe-updates-title">Есть обновлённые ингредиенты</h2>
            <p>
              {formatIngredientUpdateSummary(updateableIngredientsCount, incompatibleIngredientsCount)}
            </p>
          </div>
          <button className="button button--secondary" type="button" disabled={isUpdatingIngredients || updateableIngredientsCount === 0} onClick={() => void updateIngredients()}>{isUpdatingIngredients ? 'Обновление…' : 'Обновить ингредиенты'}</button>
        </section>
      ) : null}

      <RecipeVersionCard details={selectedVersionDetails} />

      <section className="version-history" aria-labelledby="recipe-version-history-title">
        <h2 id="recipe-version-history-title">История версий</h2>
        <ol>
          {[...details.versions].reverse().map((version) => (
            <li key={version.id} className={version.id === selectedVersionId ? 'version-history__item version-history__item--selected' : 'version-history__item'}>
              <button className="version-history__button" type="button" onClick={() => void selectVersion(version.id)}>
                <span><strong>v{version.versionNumber}</strong><em>{version.id === details.currentVersion.id ? 'Текущая' : new Date(version.createdAt).toLocaleDateString('ru-RU')}</em></span>
                <p>{getRecipePrimaryNutrition(version)} · {formatRecipeNutrition(toNutrition(version))}</p>
              </button>
            </li>
          ))}
        </ol>
      </section>
    </section>
  )
}

export function RecipeVersionCard({ details }: { details: RecipeVersionDetails }) {
  const { version } = details

  return (
    <section className="recipe-version-card" aria-labelledby="recipe-version-title">
      <div className="section-heading">
        <h2 id="recipe-version-title">Версия v{version.versionNumber}</h2>
        <span className="version-badge">{getRecipePrimaryNutrition(version)}</span>
      </div>
      <p className="recipe-version-card__total">Итого: {formatRecipeNutrition(toNutrition(version))}</p>
      <ul className="recipe-ingredient-list">
        {details.ingredients.map(({ ingredient, product, productVersion, nutrition }) => (
          <li key={ingredient.id}>
            <div>
              <strong>{product?.name ?? 'Удалённый продукт'}</strong>
              <span>v{productVersion?.versionNumber ?? '?'} · {formatDiaryNumber(ingredient.amount)} {formatIngredientUnit(ingredient.unit, productVersion)}</span>
            </div>
            <span>{formatDiaryNumber(nutrition.calories)} ккал</span>
          </li>
        ))}
      </ul>
      <dl className="recipe-output-grid">
        {version.cookedWeight === undefined ? null : <div><dt>Вес готового блюда</dt><dd>{formatDiaryNumber(version.cookedWeight)} г</dd></div>}
        {version.servingsCount === undefined ? null : <div><dt>Количество изделий</dt><dd>{formatDiaryNumber(version.servingsCount)} шт</dd></div>}
        {details.per100g === undefined ? null : <div><dt>На 100 г</dt><dd>{formatRecipeNutrition(details.per100g)}</dd></div>}
        {details.perServing === undefined ? null : <div><dt>На 1 шт</dt><dd>{formatRecipeNutrition(details.perServing)}</dd></div>}
      </dl>
    </section>
  )
}

function formatIngredientUnit(unit: string, productVersion: RecipeVersionDetails['ingredients'][number]['productVersion']): string {
  if (productVersion === undefined) {
    return unit === 'piece' ? 'шт' : unit
  }

  return getDiaryUnitOptions(productVersion).find((option) => option.value === unit)?.label ?? unit
}

function formatIngredientUpdateSummary(updateableCount: number, incompatibleCount: number): string {
  if (incompatibleCount === 0) {
    return updateableCount === 1 ? 'Один ингредиент доступен в новой версии.' : `${updateableCount} ингредиента доступны в новых версиях.`
  }

  if (updateableCount === 0) {
    return 'У обновлённых продуктов больше нет прежней единицы. Замените ингредиенты вручную.'
  }

  return `${updateableCount} ингредиента можно обновить. Ещё ${incompatibleCount} замените вручную: прежняя единица больше недоступна.`
}
