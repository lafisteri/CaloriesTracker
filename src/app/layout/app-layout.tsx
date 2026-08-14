import { Outlet, useMatch } from 'react-router-dom'

import { BottomNavigation } from '@/app/layout/bottom-navigation'

export function AppLayout() {
  const isDiarySelectionRoute = useMatch({ path: '/diary/:date/:mealType/add', end: true }) !== null
  const isDiaryAmountRoute = useMatch('/diary/:date/:mealType/add/:sourceType/:sourceId') !== null
  const isLegacyDiaryAmountRoute = useMatch('/diary/:date/:mealType/add/:sourceId') !== null
  const isDiaryBarcodeScannerRoute = useMatch('/diary/:date/:mealType/add/scan') !== null
  const isProductBarcodeScannerRoute = useMatch('/products/scan') !== null
  const isNewRecipeRoute = useMatch('/recipes/new') !== null
  const isRecipeEditRoute = useMatch('/recipes/:recipeId/edit') !== null
  const isDiaryAddRouteWithNavigation = isDiarySelectionRoute || isDiaryAmountRoute || isLegacyDiaryAmountRoute
  const isFocusedFullScreenFlow = isDiaryBarcodeScannerRoute || isProductBarcodeScannerRoute || isNewRecipeRoute || isRecipeEditRoute
  const isFullScreenFlow = isDiaryAddRouteWithNavigation || isFocusedFullScreenFlow
  const contentClassName = isFocusedFullScreenFlow
    ? 'app-content app-content--flow'
    : isDiaryAddRouteWithNavigation
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
