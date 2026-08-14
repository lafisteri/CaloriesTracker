import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'

import type { RecipeIngredientDraft, RecipePreview } from '@/application/recipes/recipe-service'
import type { ProductListItem } from '@/application/products/product-service'
import { applicationServices } from '@/app/providers/application-services'
import { getDiaryUnitOptions, type DiaryUnitOption } from '@/domain/diary/diary-unit'
import { formatDiaryNumber } from '@/features/diary/diary-formatters'
import { ProductList } from '@/features/products/product-list'
import { ProductSearchField } from '@/features/products/product-search-field'

import { formatRecipeNutrition } from './recipe-formatters'

interface RecipeIngredientForm extends RecipeIngredientDraft {
  productName: string
  versionNumber: number
  unitOptions: DiaryUnitOption[]
}

export function RecipeFormPage() {
  const { recipeId } = useParams()
  const navigate = useNavigate()
  const isEditing = recipeId !== undefined
  const [name, setName] = useState('')
  const [ingredients, setIngredients] = useState<RecipeIngredientForm[]>([])
  const [cookedWeight, setCookedWeight] = useState('')
  const [servingsCount, setServingsCount] = useState('')
  const [preview, setPreview] = useState<RecipePreview | undefined>()
  const [isLoading, setIsLoading] = useState(isEditing)
  const [isSaving, setIsSaving] = useState(false)
  const [isPickerOpen, setIsPickerOpen] = useState(false)
  const [isMissing, setIsMissing] = useState(false)
  const [error, setError] = useState<string | undefined>()
  const previewRequestId = useRef(0)
  const isSubmittingRef = useRef(false)

  useEffect(() => {
    let isMounted = true

    async function loadRecipe(): Promise<void> {
      if (recipeId === undefined) {
        return
      }

      try {
        const details = await applicationServices.recipes.getById(recipeId)

        if (!isMounted) {
          return
        }

        if (details === undefined) {
          setIsMissing(true)
          return
        }

        setName(details.recipe.name)
        setCookedWeight(details.currentVersion.cookedWeight === undefined ? '' : String(details.currentVersion.cookedWeight))
        setServingsCount(details.currentVersion.servingsCount === undefined ? '' : String(details.currentVersion.servingsCount))
        setIngredients(details.currentVersionDetails.ingredients.map(({ ingredient, product, productVersion }) => ({
          id: ingredient.id,
          productId: ingredient.productId,
          productVersionId: ingredient.productVersionId,
          amount: ingredient.amount,
          unit: ingredient.unit,
          productName: product?.name ?? 'Удалённый продукт',
          versionNumber: productVersion?.versionNumber ?? 0,
          unitOptions: productVersion === undefined ? [] : getDiaryUnitOptions(productVersion),
        })))
      } catch (loadError) {
        console.error('Failed to load recipe for editing.', loadError)

        if (isMounted) {
          setError('Не удалось загрузить рецепт.')
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

  const draft = useMemo(() => ({
    name,
    ingredients: ingredients.map(({ id, productId, productVersionId, amount, unit }) => ({ id, productId, productVersionId, amount, unit })),
    cookedWeight: parseOptionalNumber(cookedWeight),
    servingsCount: parseOptionalNumber(servingsCount),
  }), [cookedWeight, ingredients, name, servingsCount])

  useEffect(() => {
    const requestId = ++previewRequestId.current

    if (ingredients.length === 0 || ingredients.some((ingredient) => !isPositiveFinite(ingredient.amount))) {
      setPreview(undefined)
      return
    }

    async function loadPreview(): Promise<void> {
      try {
        const calculated = await applicationServices.recipes.preview(draft)

        if (requestId === previewRequestId.current) {
          setPreview(calculated)
        }
      } catch {
        if (requestId === previewRequestId.current) {
          setPreview(undefined)
        }
      }
    }

    void loadPreview()
  }, [draft, ingredients])

  const hasOutputUnit = isPositiveFinite(draft.cookedWeight) || (Number.isInteger(draft.servingsCount) && isPositiveFinite(draft.servingsCount))
  const canSave = name.trim().length > 0 && ingredients.length > 0 && ingredients.every((ingredient) => isPositiveFinite(ingredient.amount)) && hasOutputUnit && preview !== undefined

  function addIngredient(product: ProductListItem, amount: number, unit: string): void {
    setIngredients((current) => [
      ...current,
      {
        productId: product.product.id,
        productVersionId: product.currentVersion.id,
        amount,
        unit,
        productName: product.product.name,
        versionNumber: product.currentVersion.versionNumber,
        unitOptions: getDiaryUnitOptions(product.currentVersion),
      },
    ])
    setIsPickerOpen(false)
  }

  function updateIngredient(index: number, changes: Partial<Pick<RecipeIngredientForm, 'amount' | 'unit'>>): void {
    setIngredients((current) => current.map((ingredient, ingredientIndex) => ingredientIndex === index ? { ...ingredient, ...changes } : ingredient))
  }

  async function saveRecipe(): Promise<void> {
    if (isSubmittingRef.current || !canSave) {
      return
    }

    isSubmittingRef.current = true
    setIsSaving(true)
    setError(undefined)

    try {
      const details = recipeId === undefined
        ? await applicationServices.recipes.create(draft)
        : await applicationServices.recipes.update(recipeId, draft)
      navigate(`/recipes/${details.recipe.id}`, { replace: true })
    } catch (saveError) {
      console.error('Failed to save recipe.', saveError)
      setError('Не удалось сохранить рецепт. Проверьте ингредиенты, вес готового блюда или количество изделий.')
      isSubmittingRef.current = false
      setIsSaving(false)
    }
  }

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  if (isMissing) {
    return (
      <section className="empty-state" aria-labelledby="recipe-editor-missing-title">
        <h1 id="recipe-editor-missing-title">Рецепт не найден</h1>
        <p>Возможно, он был удалён или ссылка устарела.</p>
        <Link className="button button--secondary" to="/products?tab=recipes">К рецептам</Link>
      </section>
    )
  }

  return (
    <section className="recipe-editor" aria-labelledby="recipe-editor-title">
      <header className="diary-add-page__header">
        <Link className="back-link diary-add-page__back" to={isEditing && recipeId !== undefined ? `/recipes/${recipeId}` : '/products?tab=recipes'}>‹ {isEditing ? 'Изменить рецепт' : 'Новый рецепт'}</Link>
      </header>
      <div className="recipe-editor__scroll">
        <div className="diary-add-page__intro">
          <h1 id="recipe-editor-title">{isEditing ? 'Изменить рецепт' : 'Новый рецепт'}</h1>
          <p>Ингредиенты закрепляются за конкретными версиями продуктов.</p>
        </div>
        <div className="form-field">
          <label htmlFor="recipe-name">Название</label>
          <input id="recipe-name" autoFocus={!isEditing} autoComplete="off" value={name} onChange={(event) => setName(event.target.value)} />
        </div>

        <section className="recipe-editor__ingredients" aria-labelledby="recipe-ingredients-title">
          <div className="diary-selection-sections__heading">
            <h2 id="recipe-ingredients-title">Ингредиенты</h2>
            <button className="button button--secondary button--small" type="button" onClick={() => setIsPickerOpen(true)}>+ Добавить</button>
          </div>
          {ingredients.length === 0 ? <p className="form-empty">Добавьте хотя бы один продукт из вашей базы.</p> : null}
          <ul className="recipe-editor__ingredient-list">
            {ingredients.map((ingredient, index) => {
              const nutrition = preview?.ingredients[index]?.nutrition
              return (
                <li key={ingredient.id ?? `${ingredient.productVersionId}-${index}`}>
                  <div className="recipe-editor__ingredient-heading">
                    <div><strong>{ingredient.productName}</strong><span>v{ingredient.versionNumber}</span></div>
                    <button className="icon-button" type="button" aria-label={`Удалить ${ingredient.productName}`} onClick={() => setIngredients((current) => current.filter((_, ingredientIndex) => ingredientIndex !== index))}>×</button>
                  </div>
                  <div className="recipe-editor__ingredient-inputs">
                    <input
                      aria-label={`Количество ${ingredient.productName}`}
                      type="number"
                      inputMode="decimal"
                      min="0"
                      step="any"
                      value={Number.isFinite(ingredient.amount) ? ingredient.amount : ''}
                      onChange={(event) => updateIngredient(index, { amount: Number(event.target.value) })}
                    />
                    <select aria-label={`Единица ${ingredient.productName}`} value={ingredient.unit} onChange={(event) => updateIngredient(index, { unit: event.target.value })}>
                      {ingredient.unitOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                    </select>
                    <span>{nutrition === undefined ? '—' : `${formatDiaryNumber(nutrition.calories)} ккал`}</span>
                  </div>
                </li>
              )
            })}
          </ul>
        </section>

        <RecipePreviewSummary preview={preview} />

        <section className="recipe-editor__outputs" aria-labelledby="recipe-output-title">
          <h2 id="recipe-output-title">Выход блюда</h2>
          <div className="form-field">
            <label htmlFor="recipe-cooked-weight">Вес готового блюда <span>необязательно</span></label>
            <div className="input-with-unit"><input id="recipe-cooked-weight" type="number" inputMode="decimal" min="0" step="any" value={cookedWeight} onChange={(event) => setCookedWeight(event.target.value)} /><span>г</span></div>
          </div>
          <div className="form-field">
            <label htmlFor="recipe-servings">Количество изделий <span>необязательно</span></label>
            <div className="input-with-unit"><input id="recipe-servings" type="number" inputMode="numeric" min="0" step="1" value={servingsCount} onChange={(event) => setServingsCount(event.target.value)} /><span>шт</span></div>
          </div>
          {!hasOutputUnit ? <p className="field-error">Укажите вес готового блюда или целое количество изделий.</p> : null}
        </section>
        {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
        <div className="recipe-editor__actions">
          <button className="button button--primary" type="button" disabled={!canSave || isSaving} onClick={() => void saveRecipe()}>{isSaving ? 'Сохранение…' : 'Сохранить рецепт'}</button>
        </div>
      </div>
      {isPickerOpen ? <RecipeIngredientPicker onClose={() => setIsPickerOpen(false)} onAdd={addIngredient} /> : null}
    </section>
  )
}

function RecipePreviewSummary({ preview }: { preview: RecipePreview | undefined }) {
  if (preview === undefined) {
    return <p className="nutrition-preview nutrition-preview--empty">Добавьте корректные ингредиенты, чтобы увидеть итоговое КБЖУ.</p>
  }

  return (
    <section className="recipe-preview" aria-labelledby="recipe-preview-title">
      <h2 id="recipe-preview-title">Итого</h2>
      <p>{formatRecipeNutrition(preview.total)}</p>
      {preview.per100g === undefined ? null : <p>На 100 г: {formatRecipeNutrition(preview.per100g)}</p>}
      {preview.perServing === undefined ? null : <p>На 1 шт: {formatRecipeNutrition(preview.perServing)}</p>}
    </section>
  )
}

function RecipeIngredientPicker({ onClose, onAdd }: { onClose: () => void; onAdd: (product: ProductListItem, amount: number, unit: string) => void }) {
  const [query, setQuery] = useState('')
  const [products, setProducts] = useState<ProductListItem[]>([])
  const [selectedProduct, setSelectedProduct] = useState<ProductListItem | undefined>()
  const [amount, setAmount] = useState('')
  const [unit, setUnit] = useState('')
  const [hasLoadedProducts, setHasLoadedProducts] = useState(false)
  const [error, setError] = useState<string | undefined>()
  const requestId = useRef(0)

  const loadProducts = useCallback(async (searchQuery: string) => {
    const id = ++requestId.current

    try {
      const found = await applicationServices.products.search(searchQuery)

      if (id === requestId.current) {
        setProducts(found)
      }
    } catch (loadError) {
      console.error('Failed to load ingredient products.', loadError)

      if (id === requestId.current) {
        setError('Не удалось загрузить продукты.')
      }
    } finally {
      if (id === requestId.current) {
        setHasLoadedProducts(true)
      }
    }
  }, [])

  useEffect(() => {
    void loadProducts(query)
  }, [loadProducts, query])

  const isInitialLoading = !hasLoadedProducts

  const preview = useMemo(() => {
    if (selectedProduct === undefined || !isPositiveFinite(Number(amount)) || unit === '') {
      return undefined
    }

    try {
      return applicationServices.diary.previewProduct(selectedProduct, Number(amount), unit)
    } catch {
      return undefined
    }
  }, [amount, selectedProduct, unit])

  function selectProduct(product: ProductListItem): void {
    const [defaultUnit] = getDiaryUnitOptions(product.currentVersion)
    setSelectedProduct(product)
    setUnit(defaultUnit.value)
    setAmount(String(product.currentVersion.baseAmount))
  }

  return (
    <section className="recipe-ingredient-picker" aria-labelledby="ingredient-picker-title">
      <header className="diary-add-page__header">
        <button className="back-link diary-add-page__back" type="button" onClick={selectedProduct === undefined ? onClose : () => setSelectedProduct(undefined)}>‹ {selectedProduct === undefined ? 'Выбрать ингредиент' : selectedProduct.product.name}</button>
      </header>
      <div className="diary-add-page__scroll">
        {selectedProduct === undefined ? (
          <>
            <div className="diary-add-page__intro"><h1 id="ingredient-picker-title">Выбрать ингредиент</h1><p>Используется текущая версия продукта.</p></div>
            <ProductSearchField value={query} onChange={setQuery} placeholder="Поиск продукта..." autoFocus />
            {isInitialLoading ? <p className="status-message">Загрузка…</p> : null}
            {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
            {!isInitialLoading && error === undefined && products.length === 0 ? <p className="form-empty">Продукты не найдены.</p> : null}
            {!isInitialLoading && error === undefined && products.length > 0 ? <ProductList products={products} onSelect={selectProduct} /> : null}
          </>
        ) : (
          <>
            <div className="diary-add-page__intro"><h1 id="ingredient-picker-title">{selectedProduct.product.name}</h1><p>v{selectedProduct.currentVersion.versionNumber}</p></div>
            <div className="form-field"><label htmlFor="ingredient-amount">Количество</label><input id="ingredient-amount" autoFocus type="number" inputMode="decimal" min="0" step="any" value={amount} onChange={(event) => setAmount(event.target.value)} /></div>
            <div className="form-field"><label htmlFor="ingredient-unit">Единица</label><select id="ingredient-unit" value={unit} onChange={(event) => setUnit(event.target.value)}>{getDiaryUnitOptions(selectedProduct.currentVersion).map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>
            {preview === undefined ? <p className="nutrition-preview nutrition-preview--empty">Укажите корректное количество.</p> : <p className="nutrition-preview">{formatRecipeNutrition(preview)}</p>}
            <div className="diary-add-page__actions"><button className="button button--primary" type="button" disabled={preview === undefined} onClick={() => onAdd(selectedProduct, Number(amount), unit)}>Добавить ингредиент</button></div>
          </>
        )}
      </div>
    </section>
  )
}

function parseOptionalNumber(value: string): number | undefined {
  return value.trim() === '' ? undefined : Number(value)
}

function isPositiveFinite(value: number | undefined): value is number {
  return value !== undefined && Number.isFinite(value) && value > 0
}
