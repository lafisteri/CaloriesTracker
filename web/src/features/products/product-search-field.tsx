interface ProductSearchFieldProps {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  autoFocus?: boolean
  label?: string
}

/** Shared local product search field for catalog management and Diary selection. */
export function ProductSearchField({
  value,
  onChange,
  placeholder = 'Поиск продукта...',
  autoFocus = false,
  label = 'Поиск продуктов',
}: ProductSearchFieldProps) {
  return (
    <div className="search-field">
      <label>
        <span className="sr-only">{label}</span>
        <input
          autoFocus={autoFocus}
          type="search"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
        />
      </label>
      {value === '' ? null : (
        <button className="search-field__clear" type="button" onClick={() => onChange('')} aria-label="Очистить поиск">
          ×
        </button>
      )}
    </div>
  )
}
