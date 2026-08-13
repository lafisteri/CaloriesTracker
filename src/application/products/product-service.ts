import type { Product } from '@/domain/products/product'
import type { ProductDraft } from '@/domain/products/product-draft'
import type { ProductVersion } from '@/domain/products/product-version'
import { getServingConversionUnitForBase } from '@/domain/products/product-units'
import type { ServingUnit } from '@/domain/products/serving-unit'
import type { ProductRepository } from '@/domain/repositories/product-repository'
import { createUuid } from '@/shared/utils/create-uuid'

export interface ProductListItem {
  product: Product
  currentVersion: ProductVersion
}

export interface ProductDetails extends ProductListItem {
  versions: ProductVersion[]
}

export class ProductService {
  constructor(private readonly productRepository: ProductRepository) {}

  async search(query = ''): Promise<ProductListItem[]> {
    const normalizedQuery = query.trim().toLocaleLowerCase()
    const products = await this.productRepository.getActive()
    const matchedProducts = products.filter((product) => {
      if (normalizedQuery.length === 0) {
        return true
      }

      return product.name.toLocaleLowerCase().includes(normalizedQuery)
        || product.barcode?.includes(query.trim()) === true
    })

    const items = await Promise.all(
      matchedProducts.map(async (product) => {
        const currentVersion = await this.productRepository.getVersionById(product.currentVersionId)

        return currentVersion === undefined ? undefined : { product, currentVersion }
      }),
    )

    return items.filter((item): item is ProductListItem => item !== undefined)
  }

  async getById(id: string): Promise<ProductDetails | undefined> {
    const product = await this.productRepository.getById(id)

    if (product === undefined || product.deletedAt !== undefined) {
      return undefined
    }

    const [currentVersion, versions] = await Promise.all([
      this.productRepository.getVersionById(product.currentVersionId),
      this.productRepository.getVersions(product.id),
    ])

    if (currentVersion === undefined) {
      return undefined
    }

    return { product, currentVersion, versions }
  }

  async create(draft: ProductDraft): Promise<ProductDetails> {
    assertValidProductDraft(draft)

    const now = new Date().toISOString()
    const productId = createUuid()
    const barcode = normalizeBarcode(draft.barcode)
    await this.assertBarcodeIsAvailable(barcode)
    const version = createVersion(productId, 1, draft, now)
    const product: Product = {
      id: productId,
      name: draft.name.trim(),
      barcode,
      currentVersionId: version.id,
      createdAt: now,
      updatedAt: now,
    }

    await this.productRepository.create(product, version)

    return { product, currentVersion: version, versions: [version] }
  }

  async update(id: string, draft: ProductDraft): Promise<ProductDetails> {
    assertValidProductDraft(draft)

    const details = await this.getById(id)

    if (details === undefined) {
      throw new ProductNotFoundError()
    }

    const now = new Date().toISOString()
    const barcode = normalizeBarcode(draft.barcode)
    await this.assertBarcodeIsAvailable(barcode, details.product.id)
    const updatedProduct: Product = {
      ...details.product,
      name: draft.name.trim(),
      barcode,
      updatedAt: now,
    }

    if (!hasVersionChanged(details.currentVersion, draft)) {
      await this.productRepository.update(updatedProduct)

      return { ...details, product: updatedProduct }
    }

    const version = createVersion(updatedProduct.id, details.currentVersion.versionNumber + 1, draft, now)
    updatedProduct.currentVersionId = version.id

    await this.productRepository.addVersionAndUpdateProduct(updatedProduct, version)

    return {
      product: updatedProduct,
      currentVersion: version,
      versions: [...details.versions, version],
    }
  }

  async softDelete(id: string): Promise<void> {
    const product = await this.productRepository.getById(id)

    if (product === undefined || product.deletedAt !== undefined) {
      throw new ProductNotFoundError()
    }

    await this.productRepository.softDelete(id, new Date().toISOString())
  }

  private async assertBarcodeIsAvailable(barcode: string | undefined, productId?: string): Promise<void> {
    if (barcode === undefined) {
      return
    }

    const productWithBarcode = await this.productRepository.getByBarcode(barcode)

    if (productWithBarcode !== undefined && productWithBarcode.id !== productId) {
      throw new DuplicateBarcodeError()
    }
  }
}

export class ProductNotFoundError extends Error {
  constructor() {
    super('Product not found.')
    this.name = 'ProductNotFoundError'
  }
}

export class DuplicateBarcodeError extends Error {
  constructor() {
    super('A product with this barcode already exists.')
    this.name = 'DuplicateBarcodeError'
  }
}

export class InvalidProductDraftError extends Error {
  constructor() {
    super('Product draft contains invalid values.')
    this.name = 'InvalidProductDraftError'
  }
}

function createVersion(productId: string, versionNumber: number, draft: ProductDraft, createdAt: string): ProductVersion {
  return {
    id: createUuid(),
    productId,
    versionNumber,
    baseUnitType: draft.baseUnitType,
    baseAmount: draft.baseAmount,
    calories: draft.calories,
    protein: draft.protein,
    fat: draft.fat,
    carbs: draft.carbs,
    servingUnits: draft.servingUnits.map(createServingUnit),
    createdAt,
  }
}

function createServingUnit(draft: ProductDraft['servingUnits'][number]): ServingUnit {
  return {
    id: createUuid(),
    name: draft.name.trim(),
    conversionAmount: draft.conversionAmount,
    conversionUnit: draft.conversionUnit,
  }
}

function hasVersionChanged(version: ProductVersion, draft: ProductDraft): boolean {
  return version.baseUnitType !== draft.baseUnitType
    || version.baseAmount !== draft.baseAmount
    || version.calories !== draft.calories
    || version.protein !== draft.protein
    || version.fat !== draft.fat
    || version.carbs !== draft.carbs
    || !areServingUnitsEqual(version.servingUnits, draft.servingUnits)
}

function areServingUnitsEqual(
  savedUnits: ServingUnit[],
  draftUnits: ProductDraft['servingUnits'],
): boolean {
  return savedUnits.length === draftUnits.length && savedUnits.every((unit, index) => {
    const draft = draftUnits[index]

    return unit.name === draft.name.trim()
      && unit.conversionAmount === draft.conversionAmount
      && unit.conversionUnit === draft.conversionUnit
  })
}

function normalizeBarcode(barcode: string | undefined): string | undefined {
  const normalizedBarcode = barcode?.trim()

  return normalizedBarcode === '' ? undefined : normalizedBarcode
}

function assertValidProductDraft(draft: ProductDraft): void {
  if (draft.name.trim().length === 0 || !Number.isFinite(draft.baseAmount) || draft.baseAmount <= 0) {
    throw new InvalidProductDraftError()
  }

  const nutritionValues = [draft.calories, draft.protein, draft.fat, draft.carbs]

  if (nutritionValues.some((value) => !Number.isFinite(value) || value < 0)) {
    throw new InvalidProductDraftError()
  }

  if (draft.servingUnits.some((unit) => unit.name.trim().length === 0
    || !Number.isFinite(unit.conversionAmount)
    || unit.conversionAmount <= 0)) {
    throw new InvalidProductDraftError()
  }

  const expectedConversionUnit = getServingConversionUnitForBase(draft.baseUnitType)

  if ((expectedConversionUnit === undefined && draft.servingUnits.length > 0)
    || draft.servingUnits.some((unit) => unit.conversionUnit !== expectedConversionUnit)) {
    throw new InvalidProductDraftError()
  }
}
