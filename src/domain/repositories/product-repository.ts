import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'

export interface ProductRepository {
  save(product: Product): Promise<void>
  getById(id: string): Promise<Product | undefined>
  getActive(): Promise<Product[]>
  getByBarcode(barcode: string): Promise<Product | undefined>
  saveVersion(version: ProductVersion): Promise<void>
  getVersions(productId: string): Promise<ProductVersion[]>
  getVersionById(id: string): Promise<ProductVersion | undefined>
}
