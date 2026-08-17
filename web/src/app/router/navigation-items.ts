export interface BottomNavigationItem {
  label: string
  to: string
}

export const bottomNavigationItems: readonly BottomNavigationItem[] = [
  { label: 'Статистика', to: '/dashboard' },
  { label: 'Сегодня', to: '/' },
  { label: 'Продукты', to: '/products' },
]
