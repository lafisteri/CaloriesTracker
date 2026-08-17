# PRODUCT_SPEC

**Status:** Current product specification
**Last updated:** 2026-08-17

This document describes the current intended behavior of the application. If it conflicts with older phase prompts or historical planning notes, this document is the source of truth for product behavior. The current code remains the source for implementation details.

## 1. Product overview

КБЖУ — personal, local-first PWA для учёта калорий, белков, жиров и углеводов. Приложение ориентировано прежде всего на iPhone, устанавливается на Home Screen и не требует регистрации.

Основной ежедневный сценарий:

```text
Открыть приложение
→ Сегодня
→ добавить еду
→ выбрать продукт или рецепт
→ указать количество
→ сохранить
```

Пользователь самостоятельно ведёт базу продуктов. Приложение не использует внешнюю базу питания и не меняет исторические данные задним числом.

## 2. Product principles

- Mobile-first и iPhone/PWA-first интерфейс.
- Local-first хранение и работа без аккаунта.
- Offline-capable после первого успешного запуска.
- Собственная, управляемая пользователем база продуктов и рецептов.
- Минимум действий в ежедневном food logging flow.
- Версионирование nutritional data.
- Исторические данные не должны незаметно изменяться.
- Понятный, спокойный интерфейс без геймификации и лишних функций.

## 3. Navigation and information architecture

Постоянная нижняя навигация содержит только часто используемые разделы:

```text
Статистика   → /dashboard
Сегодня      → /
Продукты     → /products
```

`/` открывает Diary для текущей локальной даты. `/?date=YYYY-MM-DD` открывает Diary выбранной даты. PWA manifest использует `/` как `start_url`, поэтому запуск с Home Screen сразу открывает дневник.

Маршрут `/today` сохранён как compatibility redirect на `/dashboard`. Неизвестные маршруты перенаправляются на `/`.

`/goals` остаётся доступным маршрутом, но не занимает постоянное место в bottom navigation. Основной вход в настройки целей — secondary action **«Настроить цели»** на экране «Статистика».

Внутри приложения нет глобальной branding-надписи **«+КБЖУ»**: заголовки показывают только полезный контекст текущего экрана.

Bottom navigation сохраняется в Diary add flow:

```text
/
/?date=YYYY-MM-DD
/add/:date/:meal
/add/:date/:meal/product/:productId
/add/:date/:meal/recipe/:recipeId
```

На Diary, Diary add flow и edit DiaryEntry активен пункт **«Сегодня»**. Scanner штрихкода, а также создание и редактирование рецепта остаются focused full-screen сценариями без bottom navigation.

## 4. Today and diary

В нижней навигации **«Сегодня»** означает дневник, а не статистику.

Обычный переход на `/` открывает текущую локальную дату. Diary date deep links поддерживаются через `/?date=YYYY-MM-DD`; внутри дневника можно перейти на прошлую или будущую дату и вернуться к сегодняшней.

Дневник содержит:

- навигацию по датам;
- компактную сводку **«За день»** с calories, целью calories при наличии и Б/Ж/У;
- четыре группы: Завтрак, Обед, Ужин и Перекусы;
- итоги каждого приёма пищи;
- записи дневника;
- действие **«Добавить»** для каждого meal type.

Сводка не является большой hero-card. Meal cards используют одинаковый compact padding со всех четырёх сторон, а между соседними DiaryEntry нет divider. Пустые секции приёмов пищи остаются компактными и содержат действие добавления; отдельной глобальной empty-state плашки для пустого дня нет.

Короткий tap по DiaryEntry открывает её редактирование. Запись можно удалить или изменить её организацию прямо в Diary:

```text
swipe справа налево → открыть «Удалить» → tap «Удалить»
long press → перетащить → изменить порядок или meal
```

Swipe сам по себе не удаляет запись и не показывает browser confirmation. Удаляется только конкретная DiaryEntry; Product, Recipe и их versions сохраняются. Meal и day totals обновляются, а удаление сохраняется локально.

Long press позволяет менять порядок entries внутри meal или переносить запись в другой meal того же дня, включая пустой meal. Пользовательский порядок хранится в `DiaryEntry.sortOrder` и сохраняется после reload. При переносе меняются только `mealType` и `sortOrder`: `date`, source/version reference, amount, unit и nutrition snapshots не изменяются. Внутри Diary жесты различаются так:

```text
tap             → edit DiaryEntry
swipe left      → открыть Delete
vertical swipe  → scroll
long press      → reorder
```

## 5. Food selection and amount flow

Основной flow добавления еды:

```text
Diary
→ Добавить
→ Products selection
→ выбрать Product или Recipe
→ Amount / Unit
→ Добавить
→ Diary
```

Контекст даты и приёма пищи передаётся в URL. После успешного добавления пользователь возвращается прямо в соответствующий дневник; completed Amount screen не должен появляться при обычном возврате назад.

### Food Selection

Это единый экран выбора продуктов и рецептов без page title **«Продукты»**. Header содержит только back navigation; дата и выбранный meal type остаются routing/data context.

Верхняя последовательность экрана:

```text
< < <
[ Сканировать ] [ Добавить ]
Поиск продукта или блюда...
```

`Добавить` открывает создание нового Product и сохраняет исходный Diary context. Search одновременно находит Products и Recipes, обновляет результаты без отдельной кнопки и имеет clear action. Секция **«Недавние»** в текущем UI не отображается.

При пустой базе показывается:

```text
В базе пока нет продуктов
Создайте первый продукт с помощью кнопки выше, чтобы добавить его в дневник.
```

Отдельной create CTA внутри empty state нет.

### Amount and units

Экран Amount для продуктов и рецептов показывает back navigation, название источника, live preview КБЖУ и CTA **«Добавить»**. Отдельный subtitle о meal type не показывается.

Последовательность экрана:

```text
< < <
source/product info
nutrition preview
[ amount ] [ unit ] [ Добавить ]
```

Amount, unit и CTA находятся в одной compact horizontal row; visible labels для amount и unit не показываются. Input и select используют согласованный compact visual style. Количество поддерживает целые и десятичные значения с подходящей numeric keyboard. При открытии Amount screen input не получает focus и его значение не выделяется автоматически: keyboard открывается после user tap. Preview и сохраняемая DiaryEntry используют один расчётный путь.

Create и edit DiaryEntry используют общий Amount UI concept. Create завершает действие CTA **«Добавить»**, edit — **«Сохранить»**. На `/entries/:entryId` пользователь может изменить только amount и unit: meal type и date сохраняются, а отдельного delete action нет. Удаление остаётся действием Diary swipe-to-delete.

## 6. Products

Пользователь ведёт собственную базу продуктов. Доступны:

- создание;
- поиск по названию и штрихкоду;
- просмотр;
- редактирование;
- soft delete;
- штрихкод;
- базовая пищевая ценность;
- история версий.

Products и Recipes доступны как отдельные вкладки management catalog на `/products`. Management mode не смешивается с Food Selection mode.

На вкладке Products порядок действий:

```text
[ Сканировать ] [ Добавить ]
[ Продукты ] [ Рецепты ]
Search
Content
```

Верхнего page header **«Продукты»** нет. На вкладке Recipes action **«Создать рецепт»** занимает тот же quick-action area; tabs и Search остаются доступны ниже.

Если Products отсутствуют, empty state показывает:

```text
Продуктов пока нет
Добавьте первый продукт с помощью кнопки выше.
```

Если Recipes отсутствуют, empty state показывает:

```text
У вас пока нет рецептов
Создайте первый рецепт с помощью кнопки выше.
```

Эти состояния не дублируют create CTA.

### Product and ProductVersion

`Product` — логическая сущность с именем, optional barcode и ссылкой на актуальную версию. Nutrition и units принадлежат `ProductVersion`.

Изменение единицы, количества, калорий, Б/Ж/У или сохранённых Serving Units создаёт новую `ProductVersion` (`v1`, `v2`, `v3` и далее). `currentVersionId` указывает на актуальную версию. Старые версии не редактируются и доступны в истории.

Новая DiaryEntry использует текущую версию. Историческая DiaryEntry сохраняет ссылку на использованную версию и собственный nutrition snapshot.

### Product form and save flow

Product create/edit form содержит Name, Barcode, **«Единица»**, **«Количество»**, calories, protein, fat и carbs. Поле единицы — select; по умолчанию выбраны граммы, а список ограничен units, поддерживаемыми data model. В create flow поля количества и nutrition изначально визуально пустые и пустое значение не трактуется как `0`; в edit flow реальный сохранённый `0` отображается как `0`. **«Пищевая ценность»** следует сразу за заголовком без дополнительного explanatory text.

Обычное создание и редактирование завершаются переходом на `/products`. При создании через `/products/new?returnTo=...` сохраняется исходный Diary return flow и его date/mealType context. На edit screen secondary action **«Версии»** открывает существующую ProductVersion history; history не открывается автоматически после Save.

### Serving Units

Продукт может иметь пользовательские единицы, например:

```text
1 кусок = 32 г
1 стакан = 250 мл
```

Пищевая ценность рассчитывается от базовой единицы через conversion и nutrition calculation. Секция редактирования **«Дополнительные единицы»** не показывается в Product create/edit UI. Уже сохранённые Serving Units остаются валидными для ProductVersion, DiaryEntry и исторических данных.

## 7. Recipes

Recipes — реализованная часть продукта, а не future feature.

Модель:

```text
Recipe
→ RecipeVersion
→ RecipeIngredient
→ ProductVersion
```

Рецепт содержит название, ингредиенты, количество и единицу каждого ингредиента, optional cooked weight и optional servings count.

Для сохранения рецепта нужны хотя бы один ингредиент и хотя бы один способ выдачи результата: cooked weight или servings count.

### Nutrition

Total nutrition — сумма nutrition всех ингредиентов.

```text
per 100 g = total / cookedWeight × 100
per serving = total / servingsCount
```

Если заданы оба значения, рецепт можно добавлять и по граммам, и по штукам. В списке и preview nutrition отображается в той же единице, к которой относится показатель.

### Recipe versioning and pinned ingredients

Изменение ингредиентов, их количества, единиц, pinned `ProductVersion`, cooked weight или servings count создаёт новую `RecipeVersion`. Старая версия остаётся неизменной.

`RecipeIngredient` хранит конкретный `productVersionId`. Рецепт не переключается автоматически на `Product.currentVersionId`.

Если продукт получает новую версию, Recipe UI может показать **«Есть обновлённые ингредиенты»**. Пользователь может вручную применить актуальные совместимые версии; это создаёт новую `RecipeVersion`.

Product и Recipe soft delete выполняются сразу, без browser confirmation dialogs. Historical versions и DiaryEntry при этом сохраняются; ошибки показываются inline в UI.

## 8. Barcode

Barcode реализован как local-only инструмент:

- сканирование камерой через нативный `BarcodeDetector`, когда он поддержан браузером;
- ручной ввод кода;
- точный поиск в локальной IndexedDB;
- использование из Products и из Food Selection.

Штрихкод — строка: leading zeros сохраняются. Он нормализуется для exact lookup и не должен дублироваться в базе, включая soft-deleted записи.

Management flow:

```text
Products
→ Scan
→ known barcode
→ Product details
```

Diary flow:

```text
Diary
→ Food Selection
→ Scan
→ known barcode
→ Amount
→ Add
→ Diary
```

Для known product используется current `ProductVersion`. Если barcode неизвестен, открывается создание продукта с заполненным кодом. При входе из Diary сохраняется исходный context даты и meal type.

Внешние barcode/product APIs сейчас не используются.

## 9. Goals

Goals задаются пользователем вручную и доступны из **«Статистика → Настроить цели»**, а также по сохранённому маршруту `/goals`.

Модель цели:

```text
WeeklyGoal
effectiveFrom
7 × DailyMacroGoal
```

Для каждого дня недели задаются calories, protein, fat и carbs. Можно скопировать значения одного дня во все дни, затем изменить отдельные дни.

Изменение создаёт новую immutable `WeeklyGoal`. Для исторической даты Diary и Statistics используют цель, актуальную на эту дату, а не сегодняшнюю цель.

## 10. Statistics

Dashboard в пользовательском интерфейсе называется **«Статистика»** и расположен на `/dashboard`. Он является вторичным аналитическим разделом, а не главным стартовым экраном. Отдельного верхнего page header **«Статистика»** нет.

Statistics показывает выбранный день и соответствующую неделю:

- недельные бары калорий;
- недельный calorie balance;
- недельное распределение Б/Ж/У.

Отдельные верхние summary cards **«Калории»** и **«Макронутриенты»** не используются. Goals доступны через compact secondary action **«Настроить цели»**. Explanatory texts **«100% = цель дня»** и **«Доля энергии»** не отображаются.

Weekly balance не считает будущие дни текущей недели как deficit. Для прошлой недели учитывается вся неделя.

Проценты Б/Ж/У считаются по энергии:

```text
Protein = grams × 4
Fat = grams × 9
Carbs = grams × 4
```

Проценты относятся к macro-derived energy. Calories в DiaryEntry остаются отдельным snapshot и могут незначительно отличаться от этой производной величины.

## 11. Versioning and historical integrity

Historical integrity — обязательное правило продукта.

DiaryEntry хранит:

- date, mealType и sortOrder;
- sourceType, sourceId и sourceVersionId;
- sourceName snapshot;
- amount и unit;
- snapshots calories, protein, fat и carbs.

После изменения Product или Recipe прошлые DiaryEntry не пересчитываются автоматически. Например, запись Pizza v1 остаётся с nutrition Pizza v1 после появления Pizza v2.

При редактировании исторической DiaryEntry расчёт выполняется через сохранённый `sourceVersionId`, а не через актуальную версию продукта или рецепта. Edit изменяет только amount и unit; существующие meal type и date сохраняются.

## 12. Storage and architecture

Текущий stack:

- React, TypeScript, Vite и React Router;
- Tailwind CSS;
- Dexie.js и IndexedDB;
- React Hook Form и Zod для форм и валидации;
- Zustand только для transient UI state;
- vite-plugin-pwa и Workbox.

Пользовательские данные хранятся локально в IndexedDB: products, productVersions, recipes, recipeVersions, diaryEntries и weeklyGoals. Diary ordering также хранится локально через `sortOrder`; обновление схемы назначает существующим entries стабильный начальный порядок без изменения historical nutrition data.

Архитектура разделяет UI, application services, domain rules, repository interfaces и Dexie implementations. UI не обращается к Dexie напрямую и не дублирует расчёты nutrition.

## 13. Offline and PWA

После первого успешного запуска приложение должно работать offline для локальных сценариев:

- Diary и добавление существующей еды;
- Products и Recipes;
- Goals;
- Statistics на локальных данных;
- local barcode lookup и ручной barcode input.

PWA поддерживает manifest, service worker, app shell cache, standalone mode, Home Screen installation, локальные icons и iPhone safe areas. Обновления service worker используют normal auto-update behavior. User data остаются в IndexedDB, а не в service worker cache.

Intended deployment model — static Vite PWA, размещённое по HTTPS. Конкретный hosting provider не является product requirement.

## 14. UX rules

- Основные food flows используют отдельные экраны, а не маленькие bottom sheet.
- Controls должны быть touch-friendly, обычно с target не менее 44 px.
- Sticky CTA учитывают safe area и не должны перекрывать поля.
- Numeric fields используют подходящие input modes.
- Клавиатура не должна мешать редактированию или сохранению.
- Длинные названия не должны создавать horizontal scroll.
- Bottom navigation предназначена только для частых разделов.
- Основные tab screens используют compact top spacing с сохранением iPhone safe area.
- Visible back navigation в focused flows унифицирована как **`< < <`** без contextual labels и отдельного divider; destination сохраняет текущий context.
- Ошибки формулируются человеческим языком и не показывают технические исключения пользователю.
- Do not use native browser alert/confirm/prompt dialogs in product UX.
- Если primary creation action уже находится в quick-action area, empty state содержит только title и короткое объяснение без повторной CTA.
- Food Selection начинается с back navigation и quick actions; Products management начинается с quick actions, затем tabs, Search и content.
- Daily workflow остаётся компактным: без oversized inputs, redundant subtitles, repeated CTA и unnecessary empty-state cards.

## 15. Out of scope

В текущий продукт не входят:

- weight tracking;
- water tracking;
- exercise, activity или steps;
- gamification, streaks и social features;
- subscriptions и ads;
- medical advice;
- AI/photo food recognition;
- external food database lookup;
- authentication, sharing и recipe photos;
- complex onboarding.

## 16. Future and deferred

Следующие возможности не реализованы и не считаются принятым планом:

- Export / Import JSON backup;
- optional Supabase backup/sync;
- optional external barcode/product lookup.

К ним следует возвращаться только после подтверждённой пользовательской потребности.

## 17. Document precedence

For intended product behavior, precedence is:

```text
Current PRODUCT_SPEC.md
>
older phase prompts
>
historical planning notes
```

Документ описывает продукт, а не историю разработки. Новые возможности не следует считать реализованными, пока они не добавлены в этот spec и в код.
