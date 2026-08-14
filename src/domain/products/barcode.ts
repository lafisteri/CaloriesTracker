/** Keeps barcodes as opaque strings: leading zeroes and every other digit stay intact. */
export function normalizeBarcode(value: string | undefined | null): string | undefined {
  const normalized = value?.trim()

  return normalized === '' || normalized === undefined ? undefined : normalized
}
