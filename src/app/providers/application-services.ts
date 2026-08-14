import { DiaryService } from '@/application/diary/diary-service'
import { GoalService } from '@/application/goals/goal-service'
import { BarcodeService } from '@/application/products/barcode-service'
import { ProductService } from '@/application/products/product-service'
import { RecipeService } from '@/application/recipes/recipe-service'
import { StatisticsService } from '@/application/statistics/statistics-service'
import { repositories } from '@/data/repositories'

/** Composition root: UI gets application services, application depends only on ports. */
const recipeService = new RecipeService(repositories.recipes, repositories.products)
const diaryService = new DiaryService(repositories.diary, repositories.products, repositories.recipes)
const goalService = new GoalService(repositories.goals)

export const applicationServices = {
  products: new ProductService(repositories.products),
  recipes: recipeService,
  barcode: new BarcodeService(repositories.products),
  diary: diaryService,
  goals: goalService,
  statistics: new StatisticsService(diaryService, goalService),
}
