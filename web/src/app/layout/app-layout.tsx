import { Outlet, useMatch } from 'react-router-dom'

import { BottomNavigation } from '@/app/layout/bottom-navigation'

export function AppLayout() {
  const isDiarySelectionRoute = useMatch({ path: '/add/:date/:mealType', end: true }) !== null
  const isDiaryAmountRoute = useMatch('/add/:date/:mealType/:sourceType/:sourceId') !== null
  const isDiaryEntryEditRoute = useMatch('/entries/:entryId') !== null
  const isDiaryBarcodeScannerRoute = useMatch('/add/:date/:mealType/scan') !== null
  const isProductBarcodeScannerRoute = useMatch('/products/scan') !== null
  const isNewRecipeRoute = useMatch('/recipes/new') !== null
  const isRecipeEditRoute = useMatch('/recipes/:recipeId/edit') !== null
  const isDiaryFlowWithNavigation = isDiarySelectionRoute || isDiaryAmountRoute || isDiaryEntryEditRoute
  const isFocusedFullScreenFlow = isDiaryBarcodeScannerRoute || isProductBarcodeScannerRoute || isNewRecipeRoute || isRecipeEditRoute
  const isFullScreenFlow = isDiaryFlowWithNavigation || isFocusedFullScreenFlow
  const contentClassName = isFocusedFullScreenFlow
    ? 'app-content app-content--flow'
    : isDiaryFlowWithNavigation
    ? 'app-content app-content--flow app-content--with-bottom-navigation'
    : 'app-content'

  return (
    <div className={isFullScreenFlow ? 'app-shell app-shell--flow' : 'app-shell'}>
      <main className={contentClassName}>
        <Outlet />
      </main>
      {isFocusedFullScreenFlow ? null : <BottomNavigation />}
    </div>
  )
}
