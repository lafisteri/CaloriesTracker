import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'

export interface ProductRepository {
  create(product: Product, initialVersion: ProductVersion): Promise<void>
  update(product: Product): Promise<void>
  addVersionAndUpdateProduct(product: Product, version: ProductVersion): Promise<void>
  getById(id: string): Promise<Product | undefined>
  getActive(): Promise<Product[]>
  getByBarcode(barcode: string): Promise<Product | undefined>
  getVersions(productId: string): Promise<ProductVersion[]>
  getVersionById(id: string): Promise<ProductVersion | undefined>
}
