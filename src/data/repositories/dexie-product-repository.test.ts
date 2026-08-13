import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { CalorieDatabase, initializeLocalDatabase } from '@/data/database/calorie-database'
import { DexieProductRepository } from '@/data/repositories/dexie-product-repository'
import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'

describe('DexieProductRepository', () => {
  let database: CalorieDatabase
  let repository: DexieProductRepository

  beforeEach(async () => {
    database = new CalorieDatabase(`calorie-tracker-test-${Date.now()}-${Math.random()}`)
    await initializeLocalDatabase(database)
    repository = new DexieProductRepository(database)
  })

  afterEach(async () => {
    database.close()
    await database.delete()
  })

  it('initializes IndexedDB and stores products separately from their versions', async () => {
    const product: Product = {
      id: 'product-1',
      name: 'Овсянка',
      barcode: '1234567890',
      currentVersionId: 'product-version-1',
      createdAt: '2026-08-13T09:00:00.000Z',
      updatedAt: '2026-08-13T09:00:00.000Z',
    }
    const version: ProductVersion = {
      id: 'product-version-1',
      productId: product.id,
      versionNumber: 1,
      baseUnitType: 'g',
      baseAmount: 100,
      calories: 366,
      protein: 12,
      fat: 6,
      carbs: 60,
      servingUnits: [],
      createdAt: '2026-08-13T09:00:00.000Z',
    }

    await repository.save(product)
    await repository.saveVersion(version)

    expect(database.isOpen()).toBe(true)
    await expect(repository.getByBarcode(product.barcode!)).resolves.toMatchObject({ id: product.id })
    await expect(repository.getVersions(product.id)).resolves.toEqual([version])
  })
})
