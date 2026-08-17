import { zodResolver } from '@hookform/resolvers/zod'
import { useEffect, useRef, useState } from 'react'
import { useFieldArray, useForm, type DefaultValues, type UseFormRegisterReturn } from 'react-hook-form'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'

import { BackLink } from '@/app/layout/back-link'
import { DuplicateBarcodeError, type ProductDetails } from '@/application/products/product-service'
import { applicationServices } from '@/app/providers/application-services'
import { normalizeBarcode } from '@/domain/products/barcode'
import type { ProductBaseUnit } from '@/domain/products/product-version'
import { getServingConversionUnitForBase } from '@/domain/products/product-units'
import { getDiaryAddSelectionPathFromReturnTo } from '@/features/diary/diary-add-routes'
import {
  baseUnitOptions,
  productFormSchema,
  toProductDraft,
  type ProductFormValues,
} from '@/features/products/product-form-schema'

const defaultValues: DefaultValues<ProductFormValues> = {
  name: '',
  barcode: '',
  baseUnitType: 'g',
  baseAmount: 100,
  calories: undefined,
  protein: undefined,
  fat: undefined,
  carbs: undefined,
  servingUnits: [],
}

const numericFieldOptions = {
  setValueAs: (value: string): number | undefined => value === '' ? undefined : Number(value),
}

export function ProductFormPage() {
  const { productId } = useParams()
  const location = useLocation()
  const navigate = useNavigate()
  const isEditing = productId !== undefined
  const diarySelectionPath = isEditing
    ? undefined
    : getDiaryAddSelectionPathFromReturnTo(new URLSearchParams(location.search).get('returnTo'))
  const scannedBarcode = isEditing ? undefined : normalizeBarcode(new URLSearchParams(location.search).get('barcode'))
  const cancelPath = diarySelectionPath ?? (productId === undefined ? '/products' : `/products/${productId}`)
  const [isLoading, setIsLoading] = useState(isEditing)
  const [loadError, setLoadError] = useState<string | undefined>()
  const [submitError, setSubmitError] = useState<string | undefined>()
  const [duplicateProductId, setDuplicateProductId] = useState<string | undefined>()
  const [isSaving, setIsSaving] = useState(false)
  const isSubmittingRef = useRef(false)
  const form = useForm<ProductFormValues>({
    resolver: zodResolver(productFormSchema),
    defaultValues: { ...defaultValues, barcode: scannedBarcode ?? '' },
  })
  const { control, formState: { errors }, handleSubmit, register, reset, setValue, watch } = form
  const { fields, replace } = useFieldArray({ control, name: 'servingUnits' })
  const baseUnitType = watch('baseUnitType')
  const servingConversionUnit = getServingConversionUnitForBase(baseUnitType)

  useEffect(() => {
    if (servingConversionUnit === undefined) {
      if (fields.length > 0) {
        replace([])
      }
      return
    }

    fields.forEach((_, index) => {
      setValue(`servingUnits.${index}.conversionUnit`, servingConversionUnit, { shouldValidate: true })
    })
  }, [fields, replace, servingConversionUnit, setValue])

  useEffect(() => {
    let isMounted = true

    async function loadProduct(): Promise<void> {
      if (productId === undefined) {
        return
      }

      setIsLoading(true)
      setLoadError(undefined)

      try {
        const product = await applicationServices.products.getById(productId)

        if (!isMounted) {
          return
        }

        if (product === undefined) {
          setLoadError('Продукт не найден.')
          return
        }

        reset(toFormValues(product))
      } catch (error) {
        console.error('Failed to load product for editing.', error)

        if (isMounted) {
          setLoadError('Не удалось загрузить продукт. Попробуйте ещё раз.')
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
  }, [productId, reset])

  const onSubmit = handleSubmit(async (values) => {
    if (isSubmittingRef.current) {
      return
    }

    isSubmittingRef.current = true
    setIsSaving(true)
    setSubmitError(undefined)
    setDuplicateProductId(undefined)

    try {
      if (productId === undefined) {
        await applicationServices.products.create(toProductDraft(values))
      } else {
        await applicationServices.products.update(productId, toProductDraft(values))
      }

      navigate(diarySelectionPath ?? '/products', { replace: true })
    } catch (error) {
      console.error('Failed to save product.', error)
      if (error instanceof DuplicateBarcodeError) {
        setDuplicateProductId(error.belongsToDeletedProduct ? undefined : error.productId)
        setSubmitError(error.belongsToDeletedProduct
          ? 'Этот штрихкод закреплён за удалённым продуктом и пока недоступен для повторного использования.'
          : 'Продукт с таким штрихкодом уже существует.')
      } else {
        setSubmitError('Не удалось сохранить продукт. Проверьте данные и попробуйте ещё раз.')
      }
      isSubmittingRef.current = false
      setIsSaving(false)
    }
  })

  if (isLoading) {
    return <p className="status-message">Загрузка…</p>
  }

  if (loadError !== undefined) {
    return (
      <section className="empty-state" aria-labelledby="product-form-error-title">
        <h1 id="product-form-error-title">Не удалось открыть продукт</h1>
        <p>{loadError}</p>
        <BackLink to={cancelPath} />
      </section>
    )
  }

  return (
    <section className="product-form-page" aria-labelledby="product-form-title">
      <BackLink to={cancelPath} />
      <div className="page-heading">
        <div>
          <h1 id="product-form-title">{isEditing ? 'Изменить продукт' : 'Новый продукт'}</h1>
          <p>{isEditing ? 'Изменение КБЖУ или единиц создаст новую версию.' : 'Пищевая ценность сохранится в первой версии продукта.'}</p>
        </div>
        {isEditing ? <Link className="button button--secondary button--small" to={`/products/${productId}`}>Версии</Link> : null}
      </div>

      <form className="product-form" noValidate onSubmit={(event) => void onSubmit(event)}>
        <div className="form-field">
          <label htmlFor="product-name">Название</label>
          <input id="product-name" autoComplete="off" autoFocus={!isEditing} {...register('name')} />
          <FieldError message={errors.name?.message} />
        </div>

        <div className="form-field">
          <label htmlFor="product-barcode">Штрихкод <span>необязательно</span></label>
          <input id="product-barcode" inputMode="numeric" autoComplete="off" {...register('barcode')} />
          <FieldError message={errors.barcode?.message} />
        </div>

        <div className="form-field">
          <label htmlFor="product-base-unit">Единица</label>
          <select id="product-base-unit" {...register('baseUnitType')}>
            {baseUnitOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </div>

        <fieldset className="form-fieldset">
          <div className="form-field">
            <label htmlFor="product-base-amount">Количество</label>
            <div className="input-with-unit">
              <input id="product-base-amount" type="number" inputMode="decimal" min="0" step="any" {...register('baseAmount', numericFieldOptions)} />
              <span>{formatBaseUnit(baseUnitType)}</span>
            </div>
            <FieldError message={errors.baseAmount?.message} />
          </div>
        </fieldset>

        <fieldset className="form-fieldset">
          <legend>Пищевая ценность</legend>
          <div className="macro-input-grid">
            <NumberField label="Калории" unit="ккал" error={errors.calories?.message} inputProps={register('calories', numericFieldOptions)} />
            <NumberField label="Белки" unit="г" error={errors.protein?.message} inputProps={register('protein', numericFieldOptions)} />
            <NumberField label="Жиры" unit="г" error={errors.fat?.message} inputProps={register('fat', numericFieldOptions)} />
            <NumberField label="Углеводы" unit="г" error={errors.carbs?.message} inputProps={register('carbs', numericFieldOptions)} />
          </div>
        </fieldset>

        {submitError === undefined ? null : (
          <div className="form-submit-error" role="alert">
            <p>{submitError}</p>
            {duplicateProductId === undefined ? null : <Link to={`/products/${duplicateProductId}`}>Открыть существующий продукт</Link>}
          </div>
        )}
        <div className="form-actions">
          <Link className="button button--secondary" to={cancelPath}>Отмена</Link>
          <button className="button button--primary" disabled={isSaving} type="submit">{isSaving ? 'Сохранение…' : 'Сохранить'}</button>
        </div>
      </form>
    </section>
  )
}

interface NumberFieldProps {
  label: string
  unit: string
  error: string | undefined
  inputProps: UseFormRegisterReturn
}

function NumberField({ label, unit, error, inputProps }: NumberFieldProps) {
  const id = `nutrition-${label}`

  return (
    <div className="form-field">
      <label htmlFor={id}>{label}</label>
      <div className="input-with-unit">
        <input id={id} type="number" inputMode="decimal" min="0" step="any" {...inputProps} />
        <span>{unit}</span>
      </div>
      <FieldError message={error} />
    </div>
  )
}

function FieldError({ message }: { message: string | undefined }) {
  return message === undefined ? null : <span className="field-error" role="alert">{message}</span>
}

function toFormValues(details: ProductDetails): ProductFormValues {
  return {
    name: details.product.name,
    barcode: details.product.barcode ?? '',
    baseUnitType: details.currentVersion.baseUnitType as ProductBaseUnit,
    baseAmount: details.currentVersion.baseAmount,
    calories: details.currentVersion.calories,
    protein: details.currentVersion.protein,
    fat: details.currentVersion.fat,
    carbs: details.currentVersion.carbs,
    servingUnits: details.currentVersion.servingUnits.map((unit) => ({
      name: unit.name,
      conversionAmount: unit.conversionAmount,
      conversionUnit: unit.conversionUnit,
    })),
  }
}

function formatBaseUnit(unit: ProductBaseUnit): string {
  const labels: Record<ProductBaseUnit, string> = {
    g: 'г',
    ml: 'мл',
    piece: 'шт',
    serving: 'порция',
  }

  return labels[unit]
}
