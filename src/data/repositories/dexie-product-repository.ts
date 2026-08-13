import type { ProductRepository } from '@/domain/repositories/product-repository'
import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'
import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'

export class DexieProductRepository implements ProductRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  async create(product: Product, initialVersion: ProductVersion): Promise<void> {
    await this.database.transaction('rw', this.database.products, this.database.productVersions, async () => {
      await this.database.productVersions.add(initialVersion)
      await this.database.products.add(product)
    })
  }

  async update(product: Product): Promise<void> {
    await this.database.products.put(product)
  }

  async addVersionAndUpdateProduct(product: Product, version: ProductVersion): Promise<void> {
    await this.database.transaction('rw', this.database.products, this.database.productVersions, async () => {
      await this.database.productVersions.add(version)
      await this.database.products.put(product)
    })
  }

  async softDelete(id: string, deletedAt: string): Promise<void> {
    await this.database.products.update(id, { deletedAt, updatedAt: deletedAt })
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

  getVersions(productId: string): Promise<ProductVersion[]> {
    return this.database.productVersions.where('productId').equals(productId).sortBy('versionNumber')
  }

  getVersionById(id: string): Promise<ProductVersion | undefined> {
    return this.database.productVersions.get(id)
  }
}
