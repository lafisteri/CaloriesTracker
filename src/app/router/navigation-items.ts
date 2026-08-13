export interface BottomNavigationItem {
  label: string
  to: string
}

export const bottomNavigationItems: readonly BottomNavigationItem[] = [
  { label: 'Сегодня', to: '/today' },
  { label: 'Дневник', to: '/diary' },
  { label: 'Продукты', to: '/products' },
  { label: 'Цели', to: '/goals' },
]
