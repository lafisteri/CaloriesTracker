interface ProductSearchFieldProps {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  autoFocus?: boolean
}

/** Shared local product search field for catalog management and Diary selection. */
export function ProductSearchField({
  value,
  onChange,
  placeholder = 'Поиск продукта...',
  autoFocus = false,
}: ProductSearchFieldProps) {
  return (
    <label className="search-field">
      <span className="sr-only">Поиск продуктов</span>
      <input
        autoFocus={autoFocus}
        type="search"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
      />
    </label>
  )
}
