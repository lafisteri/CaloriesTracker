import { NavLink } from 'react-router-dom'

import { bottomNavigationItems } from '@/app/router/navigation-items'

export function BottomNavigation() {
  return (
    <nav className="bottom-navigation" aria-label="Основная навигация">
      {bottomNavigationItems.map(({ label, to }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) => `bottom-navigation__item${isActive ? ' bottom-navigation__item--active' : ''}`}
        >
          {label}
        </NavLink>
      ))}
    </nav>
  )
}
