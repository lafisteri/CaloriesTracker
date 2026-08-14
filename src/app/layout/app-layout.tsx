import { Outlet, useMatch } from 'react-router-dom'

import { AppHeader } from '@/app/layout/app-header'
import { BottomNavigation } from '@/app/layout/bottom-navigation'

export function AppLayout() {
  const isDiarySelectionRoute = useMatch('/diary/:date/:mealType/add') !== null
  const isDiaryAmountRoute = useMatch('/diary/:date/:mealType/add/:sourceType/:sourceId') !== null
  const isLegacyDiaryAmountRoute = useMatch('/diary/:date/:mealType/add/:sourceId') !== null
  const isDiaryBarcodeScannerRoute = useMatch('/diary/:date/:mealType/add/scan') !== null
  const isProductBarcodeScannerRoute = useMatch('/products/scan') !== null
  const isNewRecipeRoute = useMatch('/recipes/new') !== null
  const isRecipeEditRoute = useMatch('/recipes/:recipeId/edit') !== null
  const isFullScreenFlow = isDiarySelectionRoute || isDiaryBarcodeScannerRoute || isDiaryAmountRoute || isLegacyDiaryAmountRoute || isProductBarcodeScannerRoute || isNewRecipeRoute || isRecipeEditRoute

  return (
    <div className={isFullScreenFlow ? 'app-shell app-shell--flow' : 'app-shell'}>
      {isFullScreenFlow ? null : <AppHeader />}
      <main className={isFullScreenFlow ? 'app-content app-content--flow' : 'app-content'}>
        <Outlet />
      </main>
      {isFullScreenFlow ? null : <BottomNavigation />}
    </div>
  )
}
