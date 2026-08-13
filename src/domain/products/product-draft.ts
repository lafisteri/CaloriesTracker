import type { ProductBaseUnit } from './product-version'
import type { ServingConversionUnit } from './serving-unit'

export interface ServingUnitDraft {
  name: string
  conversionAmount: number
  conversionUnit: ServingConversionUnit
}

/** Editable input. A saved version is derived from this value by the application layer. */
export interface ProductDraft {
  name: string
  barcode?: string
  baseUnitType: ProductBaseUnit
  baseAmount: number
  calories: number
  protein: number
  fat: number
  carbs: number
  servingUnits: ServingUnitDraft[]
}
