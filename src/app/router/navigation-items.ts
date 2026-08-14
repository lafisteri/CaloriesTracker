export interface BottomNavigationItem {
  label: string
  to: string
}

export const bottomNavigationItems: readonly BottomNavigationItem[] = [
  { label: 'Сегодня', to: '/diary' },
  { label: 'Статистика', to: '/dashboard' },
  { label: 'Продукты', to: '/products' },
]
