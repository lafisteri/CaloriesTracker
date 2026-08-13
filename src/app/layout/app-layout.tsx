import { Outlet } from 'react-router-dom'

import { AppHeader } from '@/app/layout/app-header'
import { BottomNavigation } from '@/app/layout/bottom-navigation'

export function AppLayout() {
  return (
    <div className="app-shell">
      <AppHeader />
      <main className="app-content">
        <Outlet />
      </main>
      <BottomNavigation />
    </div>
  )
}
