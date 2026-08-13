import type { ProductVersion } from '@/domain/products/product-version'
import type { ServingUnit } from '@/domain/products/serving-unit'

export interface DiaryUnitOption {
  value: string
  label: string
}

export function getDiaryUnitOptions(version: ProductVersion): DiaryUnitOption[] {
  return [
    { value: version.baseUnitType, label: formatBaseUnit(version.baseUnitType) },
    ...version.servingUnits.map((unit) => ({ value: toServingUnitValue(unit), label: unit.name })),
  ]
}

export function resolveDiaryUnit(version: ProductVersion, value: string): DiaryResolvedUnit {
  if (value === version.baseUnitType) {
    return { type: 'base', label: formatBaseUnit(version.baseUnitType) }
  }

  const servingUnit = version.servingUnits.find((unit) => toServingUnitValue(unit) === value)

  if (servingUnit === undefined) {
    throw new Error('Diary unit is not available for this product version.')
  }

  return { type: 'serving', label: servingUnit.name, servingUnit }
}

export function toServingUnitValue(unit: ServingUnit): string {
  return `serving:${unit.id}`
}

export interface DiaryResolvedUnit {
  type: 'base' | 'serving'
  label: string
  servingUnit?: ServingUnit
}

function formatBaseUnit(unit: ProductVersion['baseUnitType']): string {
  const labels: Record<ProductVersion['baseUnitType'], string> = {
    g: 'г',
    ml: 'мл',
    piece: 'шт',
    serving: 'порция',
  }

  return labels[unit]
}
