import { Outlet, useMatch } from 'react-router-dom'

import { AppHeader } from '@/app/layout/app-header'
import { BottomNavigation } from '@/app/layout/bottom-navigation'

export function AppLayout() {
  const isDiarySelectionRoute = useMatch('/diary/:date/:mealType/add') !== null
  const isDiaryAmountRoute = useMatch('/diary/:date/:mealType/add/:productId') !== null
  const isDiaryAddFlow = isDiarySelectionRoute || isDiaryAmountRoute

  return (
    <div className={isDiaryAddFlow ? 'app-shell app-shell--flow' : 'app-shell'}>
      {isDiaryAddFlow ? null : <AppHeader />}
      <main className={isDiaryAddFlow ? 'app-content app-content--flow' : 'app-content'}>
        <Outlet />
      </main>
      {isDiaryAddFlow ? null : <BottomNavigation />}
    </div>
  )
}
