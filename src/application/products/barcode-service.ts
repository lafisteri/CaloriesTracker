import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'
import type { ProductRepository } from '@/domain/repositories/product-repository'

export interface BarcodeLookupResult {
  product: Product
  currentVersion: ProductVersion
}

/** Local-only barcode lookup seam. A scanner or external lookup can be added later. */
export class BarcodeService {
  constructor(private readonly productRepository: ProductRepository) {}

  async lookup(barcode: string): Promise<BarcodeLookupResult | undefined> {
    const normalizedBarcode = barcode.trim()

    if (normalizedBarcode.length === 0) {
      return undefined
    }

    const product = await this.productRepository.getByBarcode(normalizedBarcode)

    if (product === undefined) {
      return undefined
    }

    const currentVersion = await this.productRepository.getVersionById(product.currentVersionId)

    return currentVersion === undefined ? undefined : { product, currentVersion }
  }
}
