import type { ProductVersion } from '@/domain/products/product-version'
import type { ServingUnit } from '@/domain/products/serving-unit'

/** Converts a selected serving unit without calculating nutrition. */
export class UnitConverter {
  convertServingAmount(amount: number, servingUnit: ServingUnit): ConvertedAmount {
    if (!Number.isFinite(amount) || amount < 0) {
      throw new Error('Amount must be a non-negative finite number.')
    }

    if (!Number.isFinite(servingUnit.conversionAmount) || servingUnit.conversionAmount <= 0) {
      throw new Error('Serving conversion amount must be a positive finite number.')
    }

    return {
      amount: amount * servingUnit.conversionAmount,
      unit: servingUnit.conversionUnit,
    }
  }

  toBaseAmount(productVersion: ProductVersion, amount: number, servingUnit: ServingUnit): number {
    const convertedAmount = this.convertServingAmount(amount, servingUnit)

    if (productVersion.baseUnitType === 'serving' || convertedAmount.unit !== productVersion.baseUnitType) {
      throw new Error('Serving unit is incompatible with the product base unit.')
    }

    return convertedAmount.amount
  }
}

export const unitConverter = new UnitConverter()

export interface ConvertedAmount {
  amount: number
  unit: ServingUnit['conversionUnit']
}
