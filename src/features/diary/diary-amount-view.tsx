import type { Nutrition } from '@/domain/nutrition/nutrition'
import type { DiaryUnitOption } from '@/domain/diary/diary-unit'
import { BackButton } from '@/app/layout/back-link'

import { formatDiaryNumber } from './diary-formatters'
import { isPositiveDiaryAmount } from './diary-amount-utils'

interface DiaryAmountViewProps {
  mode: 'create' | 'edit'
  sourceName: string
  amount: string
  unit: string
  unitOptions: readonly DiaryUnitOption[]
  nutrition: Nutrition | undefined
  isSaving: boolean
  error: string | undefined
  onAmountChange: (amount: string) => void
  onUnitChange: (unit: string) => void
  onSubmit: () => void
  onBack: () => void
}

/** Shared create/edit form for a Diary amount, unit, and nutrition preview. */
export function DiaryAmountView({
  mode,
  sourceName,
  amount,
  unit,
  unitOptions,
  nutrition,
  isSaving,
  error,
  onAmountChange,
  onUnitChange,
  onSubmit,
  onBack,
}: DiaryAmountViewProps) {
  const isEditMode = mode === 'edit'
  const submitLabel = isSaving ? (isEditMode ? 'Сохранение…' : 'Добавление…') : (isEditMode ? 'Сохранить' : 'Добавить')

  return (
    <section className="diary-add-page diary-add-page--with-bottom-navigation" aria-labelledby="diary-amount-title">
      <header className="diary-add-page__header">
        <BackButton className="diary-add-page__back" onClick={onBack} />
      </header>
      <div className="diary-add-page__scroll diary-amount-page__scroll">
        <div className="diary-add-page__intro">
          <h1 id="diary-amount-title">{sourceName}</h1>
        </div>
        <div className="diary-entry-form diary-amount-page__form">
          <NutritionPreview nutrition={nutrition} />
          <div className="diary-amount-page__fields">
            <div className="form-field">
              <input id="diary-add-amount" aria-label="Количество" type="number" inputMode="decimal" min="0" step="any" value={amount} onChange={(event) => onAmountChange(event.target.value)} />
              {!isPositiveDiaryAmount(amount) && amount !== '' ? <span className="field-error">Количество должно быть больше нуля.</span> : null}
            </div>
            <div className="form-field diary-amount-page__unit">
              <select id="diary-add-unit" aria-label="Единица" value={unit} onChange={(event) => onUnitChange(event.target.value)}>
                {unitOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
              </select>
            </div>
            <button className="button button--primary diary-amount-page__submit" type="button" disabled={nutrition === undefined || isSaving} onClick={onSubmit}>
              {submitLabel}
            </button>
          </div>
          {error === undefined ? null : <p className="form-submit-error" role="alert">{error}</p>}
        </div>
      </div>
    </section>
  )
}

function NutritionPreview({ nutrition }: { nutrition: Nutrition | undefined }) {
  if (nutrition === undefined) {
    return <p className="nutrition-preview nutrition-preview--empty">Укажите корректное количество, чтобы увидеть КБЖУ.</p>
  }

  return (
    <dl className="nutrition-preview">
      <div><dt>Калории</dt><dd>{formatDiaryNumber(nutrition.calories)} ккал</dd></div>
      <div><dt>Белки</dt><dd>{formatDiaryNumber(nutrition.protein)} г</dd></div>
      <div><dt>Жиры</dt><dd>{formatDiaryNumber(nutrition.fat)} г</dd></div>
      <div><dt>Углеводы</dt><dd>{formatDiaryNumber(nutrition.carbs)} г</dd></div>
    </dl>
  )
}
