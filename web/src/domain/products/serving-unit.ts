export type ServingConversionUnit = 'g' | 'ml' | 'piece'

export interface ServingUnit {
  id: string
  name: string
  conversionAmount: number
  conversionUnit: ServingConversionUnit
}
