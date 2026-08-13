import { DiaryService } from '@/application/diary/diary-service'
import { BarcodeService } from '@/application/products/barcode-service'
import { ProductService } from '@/application/products/product-service'
import { repositories } from '@/data/repositories'

/** Composition root: UI gets application services, application depends only on ports. */
export const applicationServices = {
  products: new ProductService(repositories.products),
  barcode: new BarcodeService(repositories.products),
  diary: new DiaryService(repositories.diary, repositories.products),
}
