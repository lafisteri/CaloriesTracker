# Master Prompt для Codex: PWA для учёта КБЖУ

Ты работаешь как senior full-stack engineer и архитектор.

Нужно разработать mobile-first PWA для личного учёта калорий, белков, жиров и углеводов.

Приложение предназначено в первую очередь для iPhone и должно устанавливаться на Home Screen как PWA.

Главные приоритеты:

1. Простота.
2. Скорость добавления еды.
3. Local-first архитектура.
4. Работа offline.
5. Собственная база продуктов.
6. Рецепты.
7. Версионирование продуктов и рецептов.
8. Корректная история дневника.
9. Минимум лишних функций.
10. Код должен быть понятным, модульным и пригодным для дальнейшего развития.

---

# 1. Технологический стек

Использовать:

```text
React
TypeScript
Vite
React Router
Tailwind CSS

IndexedDB
Dexie.js

Zustand

React Hook Form
Zod

Vitest
React Testing Library
Playwright

vite-plugin-pwa

Backend в будущем:
Supabase / PostgreSQL
```

Backend НЕ реализовывать на первом этапе.

Первая версия должна полностью работать локально через IndexedDB.

Архитектуру подготовить так, чтобы позднее можно было подключить Supabase через repository/sync слой без переписывания UI и domain logic.

---

# 2. Основной архитектурный принцип

Использовать слои:

```text
UI
↓
Application
↓
Domain
↓
Repositories
↓
Local Database
↓
Future Sync Layer
↓
Supabase
```

UI не должен напрямую обращаться к Dexie.

UI не должен самостоятельно выполнять расчёты КБЖУ.

Вся бизнес-логика должна находиться в domain/application слоях.

---

# 3. Предлагаемая структура проекта

```text
src/
  app/
    router/
    providers/
    layout/

  features/
    dashboard/
    diary/
    products/
    recipes/
    goals/
    barcode/

  domain/
    nutrition/
    units/
    products/
    recipes/
    diary/
    goals/
    statistics/

  data/
    database/
    repositories/
    sync/

  shared/
    ui/
    hooks/
    types/
    utils/
```

Не создавать огромные универсальные файлы.

Разделять ответственность.

---

# 4. Основные разделы приложения

Нижняя навигация:

```text
Сегодня
Дневник
Продукты
Цели
```

Приложение mobile-first.

Главная ширина и UX ориентированы на iPhone.

---

# 5. Dashboard

Главный экран показывает:

## Сегодня

Дата:

```text
‹   Чт, 13 августа   ›
```

Возможности:

- предыдущий день;
- следующий день;
- календарь;
- возврат на сегодня.

---

## Calories Card

Показывать:

```text
Калории

1640 / 2200 ккал

Осталось 560 ккал
```

Если превышено:

```text
+180 ккал к цели
```

Не использовать негативные или обвиняющие тексты.

---

## Weekly Calories Chart

Показывать:

```text
Пн Вт Ср Чт Пт Сб Вс
```

Для каждого дня:

```text
actual calories / daily goal
```

Если цель превышена, это должно визуально отображаться.

Под графиком:

```text
−799 ккал за неделю
```

или:

```text
+320 ккал к недельной цели
```

Цель каждого дня может быть разной.

---

## Macro Card

Показывать:

```text
Белки       128 / 150 г
Жиры         61 / 70 г
Углеводы    180 / 230 г
```

Также отображать недельный stacked bar chart:

```text
Protein
Fat
Carbs
```

по дням недели.

---

# 6. Дневник питания

Для каждого дня существуют группы:

```text
Завтрак
Обед
Ужин
Перекусы
```

Каждая группа содержит DiaryEntry.

Пример:

```text
Пицца домашняя
180 г
412 ккал
```

По нажатию можно показать:

```text
Белки
Жиры
Углеводы
Версия источника
```

---

# 7. Добавление еды

Основной flow:

```text
+ Добавить
↓
Недавние / Поиск
↓
Выбор продукта или рецепта
↓
Выбор единицы
↓
Количество
↓
Предпросмотр КБЖУ
↓
Добавить
```

При добавлении изменения должны мгновенно появляться:

- в дневнике;
- в дневных итогах;
- на Dashboard;
- в недельной статистике.

---

# 8. Быстрое добавление

При открытии food picker сначала показывать:

```text
Недавние
```

Недавние формировать на основе DiaryEntry.

Не показывать несколько одинаковых записей одного продукта подряд.

После блока Recent:

```text
Поиск
```

Поиск выполняется только по собственной базе.

---

# 9. Продукты

Пользователь вручную создаёт всю базу продуктов.

На MVP НЕ использовать:

- OpenFoodFacts;
- внешние API;
- готовые базы продуктов;
- AI для определения продуктов.

---

# 10. Product

Product является постоянной логической сущностью.

```ts
interface Product {
  id: string
  name: string
  barcode?: string
  currentVersionId: string
  createdAt: string
  updatedAt: string
  deletedAt?: string
}
```

Использовать UUID.

---

# 11. ProductVersion

Пищевая ценность хранится в версиях.

```ts
interface ProductVersion {
  id: string
  productId: string
  versionNumber: number

  baseUnitType: 'g' | 'ml' | 'piece' | 'serving'
  baseAmount: number

  calories: number
  protein: number
  fat: number
  carbs: number

  servingUnits: ServingUnit[]

  createdAt: string
}
```

---

# 12. ServingUnit

Пример:

```text
Хлеб:

100 г
250 ккал

1 кусок = 32 г
```

Модель:

```ts
interface ServingUnit {
  id: string
  name: string
  conversionAmount: number
  conversionUnit: 'g' | 'ml' | 'piece'
}
```

---

# 13. Версионирование продуктов

При изменении:

- calories;
- protein;
- fat;
- carbs;
- base unit;
- serving units;

НЕ изменять старую ProductVersion.

Создавать новую:

```text
v1
v2
v3
```

Product.currentVersionId переключать на новую версию.

Поиск должен использовать только текущую версию.

Историю версий показывать отдельно.

---

# 14. Расчёт продукта

Пример:

```text
350 ккал / 100 г
```

Пользователь выбирает:

```text
45 г
```

Результат:

```text
350 × 45 / 100
```

То же самое для:

```text
protein
fat
carbs
```

Создать отдельный чистый сервис:

```ts
NutritionCalculator
```

Расчёты должны быть unit-tested.

---

# 15. UnitConverter

Создать отдельный:

```ts
UnitConverter
```

Пример:

```text
1 кусок = 32 г
```

```text
2 кусочка = 64 г
```

После конвертации NutritionCalculator выполняет расчёт КБЖУ.

Не смешивать unit conversion и nutrition calculation.

---

# 16. Создание продукта

Форма:

```text
Название

Barcode optional

Базовая единица:
100 г
100 мл
1 шт
1 порция

Калории
Белки
Жиры
Углеводы

Дополнительные единицы
```

Использовать:

```text
React Hook Form
Zod
```

---

# 17. Barcode

На MVP barcode работает только с локальной базой.

Flow:

```text
Сканировать
↓
barcode
↓
поиск Product.barcode
```

Если найден:

```text
открыть текущий ProductVersion
```

Если не найден:

```text
открыть Create Product
```

Barcode должен быть уже заполнен.

Предусмотреть архитектуру BarcodeService, чтобы позднее можно было добавить внешний lookup.

---

# 18. Recipe

Recipe является логической сущностью.

```ts
interface Recipe {
  id: string
  name: string
  currentVersionId: string
  createdAt: string
  updatedAt: string
  deletedAt?: string
}
```

---

# 19. RecipeVersion

```ts
interface RecipeVersion {
  id: string
  recipeId: string
  versionNumber: number

  ingredients: RecipeIngredient[]

  totalCalories: number
  totalProtein: number
  totalFat: number
  totalCarbs: number

  cookedWeight?: number
  servingsCount?: number

  createdAt: string
}
```

---

# 20. RecipeIngredient

Каждый ингредиент должен ссылаться именно на конкретную ProductVersion.

```ts
interface RecipeIngredient {
  id: string

  productId: string
  productVersionId: string

  amount: number
  unit: string
  normalizedAmount: number
}
```

---

# 21. Создание рецепта

Flow:

```text
Новый рецепт
↓
Название
↓
Добавить продукт
↓
Количество
↓
Добавить следующий ингредиент
↓
...
↓
Готовый вес
и/или
Количество изделий
↓
Предпросмотр КБЖУ
↓
Сохранить
```

---

# 22. Пример рецепта

```text
Пицца

Мука       100 г
Молоко      50 г
Сыр        100 г
Колбаса    100 г
```

Допустим суммарно:

```text
900 ккал
45 Б
35 Ж
100 У
```

После приготовления пользователь указывает:

```text
Готовый вес = 300 г
```

Тогда:

```text
100 г готовой пиццы:

300 ккал
15 Б
11.67 Ж
33.33 У
```

---

# 23. RecipeCalculator

Создать отдельный pure service:

```ts
RecipeCalculator
```

На вход:

```text
ingredients
productVersions
amounts
units
cookedWeight
servingsCount
```

На выход:

```text
totalNutrition
nutritionPer100g
nutritionPerServing
```

Покрыть unit tests.

---

# 24. Рецепт по штукам

Пример:

```text
Сырники

1200 ккал total

12 шт
```

Результат:

```text
1 шт = 100 ккал
```

Если дополнительно:

```text
720 г
12 шт
```

то:

```text
1 шт = 60 г
```

Пользователь может добавлять рецепт:

```text
по граммам
```

или:

```text
по штукам
```

---

# 25. Версионирование рецептов

При редактировании рецепта:

НЕ изменять существующий RecipeVersion.

Создавать:

```text
Recipe v2
Recipe v3
...
```

---

# 26. Обновление ингредиентов рецепта

Если Product внутри рецепта получил новую версию:

НЕ менять рецепт автоматически.

Показывать состояние:

```text
Есть обновлённые ингредиенты
```

Кнопка:

```text
Обновить рецепт
```

После нажатия:

1. взять актуальные ProductVersion;
2. пересчитать рецепт;
3. создать новую RecipeVersion;
4. сделать её currentVersion.

---

# 27. DiaryEntry

```ts
interface DiaryEntry {
  id: string

  date: string
  mealType: 'breakfast' | 'lunch' | 'dinner' | 'snack'

  sourceType: 'product' | 'recipe'

  sourceId: string
  sourceVersionId: string

  sourceName: string

  amount: number
  unit: string

  calories: number
  protein: number
  fat: number
  carbs: number

  createdAt: string
  updatedAt: string
  deletedAt?: string
}
```

---

# 28. Snapshot rule

Это критически важное требование.

DiaryEntry хранит рассчитанные:

```text
calories
protein
fat
carbs
```

на момент добавления.

НИКОГДА автоматически не пересчитывать старые DiaryEntry.

Пример:

```text
Пицца v1
300 ккал / 100 г
```

была добавлена вчера.

Сегодня появилась:

```text
Пицца v2
320 ккал / 100 г
```

Вчерашняя запись должна оставаться:

```text
300 ккал
```

---

# 29. Цели

Пользователь сам задаёт цели.

Не рассчитывать их автоматически.

Отдельная вкладка:

```text
Цели
```

Для каждого дня недели:

```text
Понедельник
Calories
Protein
Fat
Carbs

Вторник
Calories
Protein
Fat
Carbs

...
```

---

# 30. Apply to all

Добавить возможность:

```text
Применить ко всем дням
```

После этого пользователь может отдельно изменить любой день.

---

# 31. Goal history

Цели должны иметь историю.

```ts
interface WeeklyGoal {
  id: string
  effectiveFrom: string

  monday: DailyMacroGoal
  tuesday: DailyMacroGoal
  wednesday: DailyMacroGoal
  thursday: DailyMacroGoal
  friday: DailyMacroGoal
  saturday: DailyMacroGoal
  sunday: DailyMacroGoal

  createdAt: string
}
```

```ts
interface DailyMacroGoal {
  calories: number
  protein: number
  fat: number
  carbs: number
}
```

Изменение цели создаёт новую WeeklyGoal.

---

# 32. Local Database

Использовать Dexie.

Создать таблицы минимум:

```text
products
productVersions

recipes
recipeVersions

diaryEntries

weeklyGoals
```

Не хранить данные приложения только в Zustand.

Zustand использовать исключительно для UI state.

---

# 33. Offline-first

Без интернета должны работать:

```text
просмотр
поиск
создание продукта
редактирование продукта
создание рецепта
дневник
цели
Dashboard
статистика
```

---

# 34. PWA

Настроить:

```text
manifest
service worker
offline shell
icons
standalone
safe-area
```

Приложение должно корректно работать при запуске с iPhone Home Screen.

Не забывать:

```css
env(safe-area-inset-top)
env(safe-area-inset-bottom)
```

---

# 35. iPhone UX

Особое внимание:

- fixed bottom navigation;
- safe area;
- клавиатура;
- numeric inputs;
- touch targets;
- forms;
- scroll;
- modals;
- camera permissions.

Не проектировать интерфейс как уменьшенный desktop.

---

# 36. Форматы чисел

Во внутренних расчётах использовать достаточную точность.

Не округлять промежуточные вычисления.

UI:

```text
Calories:
1642

Protein:
127.4 г

Fat:
63.8 г

Carbs:
181.2 г
```

---

# 37. Валидация

Не разрешать:

```text
negative amount
negative calories
negative macros
empty product name
recipe without ingredients
cookedWeight <= 0
servingsCount <= 0
```

если соответствующее поле используется.

---

# 38. Tests

Обязательно покрыть unit tests:

```text
NutritionCalculator
UnitConverter
RecipeCalculator
Product versioning
Recipe versioning
Goal resolution by date
Daily statistics
Weekly statistics
```

---

# 39. Critical test 1

Product:

```text
250 kcal / 100 g
```

Amount:

```text
65 g
```

Expected:

```text
162.5 kcal
```

---

# 40. Critical test 2

Recipe:

```text
Total = 900 kcal
Cooked weight = 300 g
```

Expected:

```text
100 g = 300 kcal
```

---

# 41. Critical test 3

Recipe:

```text
Total = 1200 kcal
Servings = 12
```

Expected:

```text
1 serving = 100 kcal
```

---

# 42. Critical test 4

Version history:

1. Product Cheese v1.
2. Recipe Pizza v1 uses Cheese v1.
3. Pizza v1 added to diary.
4. Create Cheese v2.
5. Update Pizza → Pizza v2.
6. Add Pizza v2.

Expected:

```text
old DiaryEntry keeps Pizza v1 values

new DiaryEntry uses Pizza v2 values
```

---

# 43. UI стиль

Использовать минималистичный карточный интерфейс.

Ориентироваться на общую информационную структуру Lose It:

- cards;
- weekly bars;
- macros;
- clear typography;
- dense but readable information.

Не копировать интерфейс Lose It pixel-by-pixel.

Не копировать:

- логотип;
- бренд;
- иконки;
- уникальную визуальную идентичность.

---

# 44. Не добавлять без запроса

НЕ добавлять самостоятельно:

```text
weight tracking
water tracking
steps
exercise
AI food recognition
photo recognition
nutrition recommendations
social features
gamification
streaks
subscriptions
ads
authentication
external food APIs
```

Если кажется, что нужна новая функция, сначала остановиться и описать предложение.

Не реализовывать её самостоятельно.

---

# 45. Правила работы над проектом

Не пытайся реализовать всё приложение одним большим изменением.

Работай по этапам.

Перед каждым этапом:

1. изучи существующий код;
2. опиши краткий план;
3. перечисли файлы, которые планируешь изменить;
4. реализуй только текущий этап;
5. запусти tests;
6. запусти TypeScript check;
7. проверь build;
8. исправь ошибки;
9. дай краткий отчёт.

Не переходи к следующему Phase без команды пользователя.

---

# 46. Phase 1

Первым этапом реализовать ТОЛЬКО foundation.

Не создавать полностью Products/Diary/Recipes.

Нужно:

```text
React + TypeScript + Vite project

Tailwind

React Router

PWA setup

Dexie setup

application layout

bottom navigation

placeholder pages:

Сегодня
Дневник
Продукты
Цели

domain types

repository interfaces

basic local database

Vitest

ESLint

TypeScript strict mode
```

---

# 47. Phase 1 UI

Сделать минимальный mobile shell:

```text
Header

Page content

Bottom nav
```

Bottom nav:

```text
Сегодня
Дневник
Продукты
Цели
```

Учитывать iPhone safe area.

Не заниматься детальным Dashboard.

---

# 48. Phase 1 data models

Создать initial domain models:

```text
Product
ProductVersion
ServingUnit

Recipe
RecipeVersion
RecipeIngredient

DiaryEntry

WeeklyGoal
DailyMacroGoal
```

Не реализовывать всю бизнес-логику.

---

# 49. Phase 1 repository interfaces

Подготовить:

```text
ProductRepository
RecipeRepository
DiaryRepository
GoalRepository
```

Создать Dexie implementations.

UI пока не должен напрямую использовать Dexie tables.

---

# 50. Phase 1 completion criteria

Phase 1 считается завершённым, если:

```text
npm install works

npm run dev works

npm run build works

tests work

PWA manifest exists

IndexedDB initializes

navigation works

all four placeholder pages open

mobile layout works

project structure follows architecture
```

---

# 51. После завершения Phase 1

ОСТАНОВИСЬ.

Не начинай Products.

В ответе покажи:

1. что было создано;
2. структуру проекта;
3. архитектурные решения;
4. команды запуска;
5. результаты tests/build;
6. что будет сделано в Phase 2.

После этого жди следующую команду.
