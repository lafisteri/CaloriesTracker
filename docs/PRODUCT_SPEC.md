# PRODUCT_SPEC

**Status:** Current product specification
**Last updated:** 2026-08-14

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
Сегодня      → /diary
Статистика   → /dashboard
Продукты     → /products
```

`/` перенаправляет на `/diary`. PWA manifest использует `/` как `start_url`, поэтому запуск с Home Screen также приводит в дневник.

Маршрут `/today` сохранён как compatibility redirect на `/dashboard`. Неизвестные маршруты перенаправляются на `/diary`.

`/goals` остаётся доступным маршрутом, но не занимает постоянное место в bottom navigation. Основной вход в настройки целей — secondary action **«Настроить цели»** на экране «Статистика».

Полноэкранные промежуточные сценарии скрывают header и bottom navigation:

- выбор еды;
- ввод количества;
- сканер штрихкода;
- создание и редактирование рецепта.

## 4. Today and diary

В нижней навигации **«Сегодня»** означает дневник, а не статистику.

Обычный переход на `/diary` всегда открывает текущую локальную дату. Diary date deep links поддерживаются через `/diary?date=YYYY-MM-DD`; внутри дневника можно перейти на прошлую или будущую дату и вернуться к сегодняшней.

Дневник содержит:

- навигацию по датам;
- дневные калории и Б/Ж/У;
- четыре группы: Завтрак, Обед, Ужин и Перекусы;
- итоги каждого приёма пищи;
- записи дневника;
- действие **«+ Добавить»** для каждого meal type.

Пустые секции приёмов пищи остаются компактными и не должны мешать добавлению. Текст пустого дня:

```text
Сегодня пока ничего не добавлено
```

или, для другой даты:

```text
За этот день ничего не добавлено
```

## 5. Food selection and amount flow

Основной flow добавления еды:

```text
Diary
→ + Добавить
→ Full-screen Food Selection
→ выбрать Product или Recipe
→ Full-screen Amount / Unit
→ Добавить
→ Diary
```

Контекст даты и приёма пищи передаётся в URL. После успешного добавления пользователь возвращается прямо в соответствующий дневник; completed Amount screen не должен появляться при обычном возврате назад.

### Food Selection

Это один общий полноэкранный экран, а не bottom sheet. В нём есть:

1. поиск по продуктам и рецептам;
2. компактный список недавних источников;
3. единая локальная база продуктов и блюд;
4. переход к сканированию и созданию продукта.

Пользователь не выбирает заранее тип «продукт или рецепт»: оба типа присутствуют в одном поиске и одном списке. Search обновляет результаты без отдельной кнопки. Поле имеет clear action и не открывает клавиатуру автоматически при каждом входе в Food Selection.

Recent хранит логическую пару `sourceType + sourceId`. При повторном добавлении используется актуальная `ProductVersion` или `RecipeVersion`, а не версия старой DiaryEntry.

### Amount and units

Экран Amount общий для продуктов и рецептов. Он показывает название источника, выбранный приём пищи, количество, доступную единицу, live preview КБЖУ и CTA **«Добавить в …»**.

Количество поддерживает целые и десятичные значения с подходящей numeric keyboard. Preview и сохраняемая DiaryEntry используют один расчётный путь.

## 6. Products

Пользователь ведёт собственную базу продуктов. Доступны:

- создание;
- поиск по названию и штрихкоду;
- просмотр;
- редактирование;
- soft delete;
- штрихкод;
- базовая пищевая ценность;
- дополнительные Serving Units;
- история версий.

Products и Recipes доступны как отдельные вкладки management catalog на `/products`. Management mode не смешивается с Food Selection mode.

### Product and ProductVersion

`Product` — логическая сущность с именем, optional barcode и ссылкой на актуальную версию. Nutrition и units принадлежат `ProductVersion`.

Изменение базовой единицы, базового количества, калорий, Б/Ж/У или дополнительных единиц создаёт новую `ProductVersion` (`v1`, `v2`, `v3` и далее). `currentVersionId` указывает на актуальную версию. Старые версии не редактируются и доступны в истории.

Новая DiaryEntry использует текущую версию. Историческая DiaryEntry сохраняет ссылку на использованную версию и собственный nutrition snapshot.

### Serving Units

Продукт может иметь пользовательские единицы, например:

```text
1 кусок = 32 г
1 стакан = 250 мл
```

Пищевая ценность рассчитывается от базовой единицы через conversion и nutrition calculation. В UI используются понятные названия единиц, а не внутренние технические поля.

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

Dashboard в пользовательском интерфейсе называется **«Статистика»** и расположен на `/dashboard`. Он является вторичным аналитическим разделом, а не главным стартовым экраном.

Statistics показывает выбранный день и соответствующую неделю:

- калории за день и дневную цель;
- статус remaining/over goal без обвиняющих формулировок;
- дневные Б/Ж/У;
- недельные бары калорий;
- недельный calorie balance;
- недельное распределение Б/Ж/У.

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

- date и mealType;
- sourceType, sourceId и sourceVersionId;
- sourceName snapshot;
- amount и unit;
- snapshots calories, protein, fat и carbs.

После изменения Product или Recipe прошлые DiaryEntry не пересчитываются автоматически. Например, запись Pizza v1 остаётся с nutrition Pizza v1 после появления Pizza v2.

При редактировании исторической DiaryEntry расчёт выполняется через сохранённый `sourceVersionId`, а не через актуальную версию продукта или рецепта.

## 12. Storage and architecture

Текущий stack:

- React, TypeScript, Vite и React Router;
- Tailwind CSS;
- Dexie.js и IndexedDB;
- React Hook Form и Zod для форм и валидации;
- Zustand только для transient UI state;
- vite-plugin-pwa и Workbox.

Пользовательские данные хранятся локально в IndexedDB: products, productVersions, recipes, recipeVersions, diaryEntries и weeklyGoals.

Архитектура разделяет UI, application services, domain rules, repository interfaces и Dexie implementations. UI не обращается к Dexie напрямую и не дублирует расчёты nutrition.

## 13. Offline and PWA

После первого успешного запуска приложение должно работать offline для локальных сценариев:

- Diary и добавление существующей еды;
- Products и Recipes;
- Goals;
- Statistics на локальных данных;
- local barcode lookup и ручной barcode input.

PWA поддерживает manifest, service worker, app shell cache, standalone mode, Home Screen installation, локальные icons и iPhone safe areas. Обновления service worker используют normal auto-update behavior. User data остаются в IndexedDB, а не в service worker cache.

## 14. UX rules

- Основные flows полноэкранные; primary food selection не является маленьким bottom sheet.
- Controls должны быть touch-friendly, обычно с target не менее 44 px.
- Sticky CTA учитывают safe area и не должны перекрывать поля.
- Numeric fields используют подходящие input modes.
- Клавиатура не должна мешать редактированию или сохранению.
- Длинные названия не должны создавать horizontal scroll.
- Bottom navigation предназначена только для частых разделов.
- Ошибки формулируются человеческим языком и не показывают технические исключения пользователю.
- Do not use native browser alert/confirm/prompt dialogs in product UX.

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
