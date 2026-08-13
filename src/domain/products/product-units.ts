import type { ProductBaseUnit } from './product-version'
import type { ServingConversionUnit } from './serving-unit'

/** Returns the only conversion unit that can be normalized to this base unit. */
export function getServingConversionUnitForBase(
  baseUnitType: ProductBaseUnit,
): ServingConversionUnit | undefined {
  return baseUnitType === 'serving' ? undefined : baseUnitType
}
