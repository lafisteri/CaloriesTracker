import { NavLink, useLocation } from 'react-router-dom'

import { bottomNavigationItems } from '@/app/router/navigation-items'

export function BottomNavigation() {
  const { pathname } = useLocation()
  const isDiaryRoute = pathname === '/' || pathname.startsWith('/add/') || pathname.startsWith('/entries/')

  return (
    <nav className="bottom-navigation" aria-label="Основная навигация">
      {bottomNavigationItems.map(({ label, to }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) => {
            const isCurrentItem = to === '/' ? isDiaryRoute : isActive

            return `bottom-navigation__item${isCurrentItem ? ' bottom-navigation__item--active' : ''}`
          }}
        >
          {label}
        </NavLink>
      ))}
    </nav>
  )
}
