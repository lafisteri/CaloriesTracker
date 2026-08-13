import type { ProductRepository } from '@/domain/repositories/product-repository'
import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'
import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'

export class DexieProductRepository implements ProductRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  async save(product: Product): Promise<void> {
    await this.database.products.put(product)
  }

  getById(id: string): Promise<Product | undefined> {
    return this.database.products.get(id)
  }

  async getActive(): Promise<Product[]> {
    return this.database.products.filter((product) => product.deletedAt === undefined).sortBy('name')
  }

  getByBarcode(barcode: string): Promise<Product | undefined> {
    return this.database.products.where('barcode').equals(barcode).and((product) => product.deletedAt === undefined).first()
  }

  async saveVersion(version: ProductVersion): Promise<void> {
    await this.database.productVersions.put(version)
  }

  getVersions(productId: string): Promise<ProductVersion[]> {
    return this.database.productVersions.where('productId').equals(productId).sortBy('versionNumber')
  }

  getVersionById(id: string): Promise<ProductVersion | undefined> {
    return this.database.productVersions.get(id)
  }
}
