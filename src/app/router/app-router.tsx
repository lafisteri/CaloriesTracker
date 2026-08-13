import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'

import { AppLayout } from '@/app/layout/app-layout'
import { DiaryPage } from '@/features/diary/diary-page'
import { GoalsPage } from '@/features/goals/goals-page'
import { ProductsPage } from '@/features/products/products-page'
import { TodayPage } from '@/features/dashboard/today-page'

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppLayout />}>
          <Route index element={<Navigate replace to="/today" />} />
          <Route path="today" element={<TodayPage />} />
          <Route path="diary" element={<DiaryPage />} />
          <Route path="products" element={<ProductsPage />} />
          <Route path="goals" element={<GoalsPage />} />
          <Route path="*" element={<Navigate replace to="/today" />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
