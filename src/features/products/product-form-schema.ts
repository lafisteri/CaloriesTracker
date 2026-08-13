import { z } from 'zod'

import type { ProductDraft } from '@/domain/products/product-draft'

const baseUnitTypeSchema = z.enum(['g', 'ml', 'piece', 'serving'])
const conversionUnitSchema = z.enum(['g', 'ml', 'piece'])
const nonNegativeNumber = z.number({ invalid_type_error: 'Укажите число.' }).finite().min(0, 'Значение не может быть отрицательным.')

export const productFormSchema = z.object({
  name: z.string().trim().min(1, 'Укажите название продукта.').max(120, 'Не более 120 символов.'),
  barcode: z.string().trim().max(64, 'Не более 64 символов.').optional(),
  baseUnitType: baseUnitTypeSchema,
  calories: nonNegativeNumber,
  protein: nonNegativeNumber,
  fat: nonNegativeNumber,
  carbs: nonNegativeNumber,
  servingUnits: z.array(z.object({
    name: z.string().trim().min(1, 'Укажите название единицы.').max(60, 'Не более 60 символов.'),
    conversionAmount: z.number({ invalid_type_error: 'Укажите число.' }).finite().positive('Количество должно быть больше нуля.'),
    conversionUnit: conversionUnitSchema,
  })).max(20, 'Можно добавить до 20 единиц.'),
})

export type ProductFormValues = z.infer<typeof productFormSchema>

const baseUnitAmounts = {
  g: 100,
  ml: 100,
  piece: 1,
  serving: 1,
} as const

export const baseUnitOptions = [
  { value: 'g', label: '100 г' },
  { value: 'ml', label: '100 мл' },
  { value: 'piece', label: '1 шт' },
  { value: 'serving', label: '1 порция' },
] as const

export function toProductDraft(values: ProductFormValues): ProductDraft {
  return {
    ...values,
    barcode: values.barcode?.trim() || undefined,
    baseAmount: baseUnitAmounts[values.baseUnitType],
  }
}
