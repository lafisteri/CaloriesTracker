import type { Nutrition } from '@/domain/nutrition/nutrition'

import type { ServingUnit } from './serving-unit'

export type ProductBaseUnit = 'g' | 'ml' | 'piece' | 'serving'

export interface ProductVersion extends Nutrition {
  id: string
  productId: string
  versionNumber: number
  baseUnitType: ProductBaseUnit
  baseAmount: number
  servingUnits: ServingUnit[]
  createdAt: string
}
