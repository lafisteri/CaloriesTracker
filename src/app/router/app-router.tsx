import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'

import { AppLayout } from '@/app/layout/app-layout'
import { DiaryPage } from '@/features/diary/diary-page'
import { DiaryEntryDetailsPage } from '@/features/diary/diary-entry-details-page'
import { GoalsPage } from '@/features/goals/goals-page'
import { ProductsPage } from '@/features/products/products-page'
import { ProductDetailsPage } from '@/features/products/product-details-page'
import { ProductFormPage } from '@/features/products/product-form-page'
import { TodayPage } from '@/features/dashboard/today-page'

const FoodSelectionPage = lazy(async () => {
  const module = await import('@/features/diary/food-selection-page')
  return { default: module.FoodSelectionPage }
})
const FoodAmountPage = lazy(async () => {
  const module = await import('@/features/diary/food-amount-page')
  return { default: module.FoodAmountPage }
})

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppLayout />}>
          <Route index element={<Navigate replace to="/today" />} />
          <Route path="today" element={<TodayPage />} />
          <Route path="diary" element={<DiaryPage />} />
          <Route path="diary/:date/:mealType/add" element={<Suspense fallback={<p className="status-message">Загрузка…</p>}><FoodSelectionPage /></Suspense>} />
          <Route path="diary/:date/:mealType/add/:productId" element={<Suspense fallback={<p className="status-message">Загрузка…</p>}><FoodAmountPage /></Suspense>} />
          <Route path="diary/entries/:entryId" element={<DiaryEntryDetailsPage />} />
          <Route path="products" element={<ProductsPage />} />
          <Route path="products/new" element={<ProductFormPage />} />
          <Route path="products/:productId" element={<ProductDetailsPage />} />
          <Route path="products/:productId/edit" element={<ProductFormPage />} />
          <Route path="goals" element={<GoalsPage />} />
          <Route path="*" element={<Navigate replace to="/today" />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
