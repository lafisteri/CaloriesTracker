import { DiaryService } from '@/application/diary/diary-service'
import { GoalService } from '@/application/goals/goal-service'
import { BarcodeService } from '@/application/products/barcode-service'
import { ProductService } from '@/application/products/product-service'
import { StatisticsService } from '@/application/statistics/statistics-service'
import { repositories } from '@/data/repositories'

/** Composition root: UI gets application services, application depends only on ports. */
const diaryService = new DiaryService(repositories.diary, repositories.products)
const goalService = new GoalService(repositories.goals)

export const applicationServices = {
  products: new ProductService(repositories.products),
  barcode: new BarcodeService(repositories.products),
  diary: diaryService,
  goals: goalService,
  statistics: new StatisticsService(diaryService, goalService),
}
