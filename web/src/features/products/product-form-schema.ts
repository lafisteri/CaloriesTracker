import { z } from 'zod'

import type { ProductDraft } from '@/domain/products/product-draft'
import { getServingConversionUnitForBase } from '@/domain/products/product-units'

const baseUnitTypeSchema = z.enum(['g', 'ml', 'piece', 'serving'])
const conversionUnitSchema = z.enum(['g', 'ml', 'piece'])
const nonNegativeNumber = z.number({ invalid_type_error: 'Укажите число.' }).finite().min(0, 'Значение не может быть отрицательным.')

export const productFormSchema = z.object({
  name: z.string().trim().min(1, 'Укажите название продукта.').max(120, 'Не более 120 символов.'),
  barcode: z.string().trim().max(64, 'Не более 64 символов.').optional(),
  baseUnitType: baseUnitTypeSchema,
  baseAmount: z.number({ invalid_type_error: 'Укажите число.' }).finite().positive('Количество должно быть больше нуля.'),
  calories: nonNegativeNumber,
  protein: nonNegativeNumber,
  fat: nonNegativeNumber,
  carbs: nonNegativeNumber,
  servingUnits: z.array(z.object({
    name: z.string().trim().min(1, 'Укажите название единицы.').max(60, 'Не более 60 символов.'),
    conversionAmount: z.number({ invalid_type_error: 'Укажите число.' }).finite().positive('Количество должно быть больше нуля.'),
    conversionUnit: conversionUnitSchema,
  })).max(20, 'Можно добавить до 20 единиц.'),
}).superRefine((values, context) => {
  const requiredConversionUnit = getServingConversionUnitForBase(values.baseUnitType)

  if (requiredConversionUnit === undefined && values.servingUnits.length > 0) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['servingUnits'],
      message: 'Для базовой единицы «порция» дополнительные единицы пока недоступны.',
    })
  }

  values.servingUnits.forEach((unit, index) => {
    if (requiredConversionUnit !== undefined && unit.conversionUnit !== requiredConversionUnit) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['servingUnits', index, 'conversionUnit'],
        message: `Для этой базовой единицы используйте «${formatConversionUnit(requiredConversionUnit)}».`,
      })
    }
  })
})

export type ProductFormValues = z.infer<typeof productFormSchema>

export const baseUnitOptions = [
  { value: 'g', label: 'Граммы' },
  { value: 'ml', label: 'Миллилитры' },
  { value: 'piece', label: 'Штуки' },
  { value: 'serving', label: 'Порции' },
] as const

export function toProductDraft(values: ProductFormValues): ProductDraft {
  return {
    ...values,
    barcode: values.barcode?.trim() || undefined,
  }
}

function formatConversionUnit(unit: 'g' | 'ml' | 'piece'): string {
  return unit === 'piece' ? 'шт' : unit
}
