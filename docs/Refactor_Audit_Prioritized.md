# CaloriesTracker — приоритизированный аудит и план рефакторинга

**Статус:** рабочий backlog после полного static-review native iOS проекта  
**Дата:** 2026-08-18  
**Режим работы:** выполнять по одному пункту, без giant refactor  
**Принцип:** сначала correctness и пользовательские ошибки, затем стабильность, затем производительность, затем архитектурная уборка и UI polish.

---

## 0. Правила выполнения

1. Один пункт = один отдельный prompt / один ограниченный scope.
2. Не смешивать technical refactor и visual redesign, если они независимы.
3. Каждый пункт должен завершаться:
   - code inspection;
   - `xcodebuild`;
   - `BUILD SUCCEEDED`;
   - без запуска Simulator;
   - physical iPhone checklist, если затронут UI/gesture/keyboard/navigation.
4. Не трогать исторические invariants:
   - immutable `ProductVersion`;
   - immutable `RecipeVersion`;
   - pinned `ProductVersion` у `RecipeIngredient`;
   - Diary snapshot;
   - edit DiaryEntry через сохранённый `sourceVersionID`;
   - move/reorder не меняет nutrition/source/date;
   - soft delete сохраняет историю;
   - `LocalDay` остаётся local civil date.
5. Не делать TCA/Redux/Coordinator framework/DI framework/Swift Packages ради самого рефакторинга.
6. Работающий keyboard/focus fix не переписывать попутно.
7. Today gestures не переписывать без отдельной подтверждённой проблемы на physical iPhone.

---

# 1. Критичность

Используем четыре уровня.

## CRITICAL

Ошибка может приводить к неверным пользовательским данным, неверному смыслу UI или опасному действию.

## HIGH

Риск crash/race, существенный performance debt, растущая сложность, которая уже мешает дальнейшей разработке.

## MEDIUM

Maintainability, лишняя работа, lifecycle, consistency. Полезно исправить, но приложение может жить и без этого.

## LOW / DEFERRED

Полировка, потенциальное архитектурное улучшение или изменение, которое сейчас рискованнее пользы.

---

# 2. Очередь выполнения

Ниже порядок, в котором рекомендуется идти по одному.

---

## CT-01 — CRITICAL — Неверные calories рядом с amount в Catalog

**Тип:** correctness / UI data accuracy  
**Приоритет:** 1  
**Статус:** TODO

### Где

- `ProductCatalogView.swift`, примерно строки 325–329
- аналогичный Recipe row в `RecipeViews.swift`, примерно строки 165–168

### Проблема

В selection row amount может быть взят из последнего использования, например:

```text
250 г
```

а calories отображаются из базовой/current nutrition версии, например:

```text
100 ккал на 100 г
```

В результате UI может показать:

```text
250 г · 100 ккал
```

вместо ожидаемых:

```text
250 г · 250 ккал
```

У Recipe есть аналогичный риск: рядом с выбранным/default amount может отображаться `totalNutrition.calories` всего рецепта, а не nutrition выбранного количества.

### Почему critical

UI сообщает пользователю фактически неверную пищевую ценность выбранного количества.

### Target

Calories в row должны рассчитываться для того amount/unit, который отображается рядом.

Использовать тот же domain/application calculation path, что и preview/save, а не отдельную формулу во View.

### Не менять

- quick-add semantics;
- Diary snapshots;
- selection navigation;
- ProductVersion/RecipeVersion logic.

### Effort

S–M

---

## CT-02 — CRITICAL — Recipe поддерживает `г` и `порция`, но Amount UI фактически не даёт выбрать unit

**Тип:** product correctness / UX  
**Приоритет:** 2  
**Статус:** DECISION REQUIRED

### Где

- `DiaryService.recipeUnitOptions()`
- `DiaryAmountView`
- shared `AmountEditorView`
- Recipe composition Amount flow

### Проблема

Domain умеет Recipe с двумя output modes:

```text
cookedWeight
servingsCount
```

и `DiaryService.recipeUnitOptions()` может вернуть:

```text
g
serving
```

Но Amount UI сейчас показывает unit как read-only text.

При наличии обеих единиц выбирается одна, фактически обычно первая (`g`).

Пользователь не может выбрать `порция`, хотя модель и расчёты это поддерживают.

### Почему critical

Пользователь может быть вынужден логировать рецепт не в той единице, которую он хочет использовать.

### Product decision

Рекомендуемый вариант:

```text
1 доступная unit
→ plain read-only text

2 доступные units
→ compact selector
```

После решения сделать отдельный implementation prompt.

### Effort

M

---

## CT-03 — CRITICAL — Default `100` для source с unit `serving`

**Тип:** correctness / dangerous default  
**Приоритет:** 3  
**Статус:** DECISION REQUIRED

### Где

- `ProductListViewModel.selectionDefault()`
- `AmountViewModel` create mode
- quick-add fallback

### Проблема

Fallback amount сейчас может быть:

```text
100
```

независимо от unit.

Для продукта:

```text
baseUnit = serving
```

это означает потенциальный default:

```text
100 порций
```

Особенно опасно в quick-add, где значение может сразу сохраниться.

### Recommended product rule

```text
g        → 100
serving  → 1
```

Последнее совместимое использованное значение имеет приоритет над fallback.

### Почему critical

Один tap по `+` потенциально может создать очевидно неверную запись.

### Effort

S

---

## CT-04 — HIGH — Concurrent quick-add race

**Тип:** correctness / concurrency  
**Приоритет:** 4  
**Статус:** TODO

### Где

- Product/Recipe Catalog selection rows
- `quickAddingProductID` и аналогичное state

### Проблема

Пока Product A добавляется, `+` у Product B может оставаться активным.

Сценарий:

```text
tap + A
tap + B
```

может создать две конкурентные async операции, которые независимо:
- сохраняют DiaryEntry;
- меняют loading state;
- управляют navigation после success.

### Target

В selection context должна быть максимум одна active quick-add operation.

На время операции:
- остальные quick-add actions disabled;
- double submit невозможен;
- completion одной операции не сбрасывает state другой.

### Effort

S

---

## CT-05 — HIGH — Unsafe `NavigationPath.removeLast()`

**Тип:** crash safety  
**Приоритет:** 5  
**Статус:** TODO

### Где

Найдены вызовы примерно в:

- `TodayView.swift` около 175
- `TodayView.swift` около 187
- `ProductCatalogView.swift` около 73

### Проблема

`removeLast()` на пустом path приводит к trap.

Сегодня flow, скорее всего, обеспечивает непустой path, но async completion/navigation reset могут нарушить это предположение.

### Target

Safe route-aware pop.

Предпочтительно:
- helper в router;
- проверка top route / non-empty path;
- не маскировать ошибку generic `if !path.isEmpty` в десятках мест.

### Effort

XS–S

---

## PF-01 — HIGH — DiaryRepository делает full-table scans

**Тип:** performance / scalability  
**Приоритет:** 6  
**Статус:** TODO

### Где

`SwiftDataRepositories.swift`

Особенно:

- Diary entries for days
- active diary entries
- latest usage defaults
- Statistics week reads

### Проблема

В некоторых repository methods сначала:

```swift
modelContext.fetch(FetchDescriptor<DiaryEntryRecord>())
```

а затем фильтрация выполняется в памяти.

Diary является постоянно растущей таблицей.

Через месяцы/годы weekly statistics или Catalog defaults будут читать намного больше данных, чем требуется.

### Target

Перенести:
- day filtering;
- deleted filtering;
- meal filtering;
- sorting

в `FetchDescriptor` / SwiftData predicates.

### Важно

Сначала query shape.

Не добавлять indexes просто «на всякий случай».

### Effort

M

---

## PF-02 — HIGH — N+1 currentVersion lookups в Catalog

**Тип:** performance / repository API  
**Приоритет:** 7  
**Статус:** TODO

### Где

- `ProductService.swift`, примерно 25–36
- `RecipeService.swift`, примерно 92–101

### Проблема

Pattern:

```text
fetch products
for each product
    fetch current version
```

Для N sources получается 1 + N persistence calls.

### Target

Batch API / purpose-specific read path.

Например conceptually:

```swift
versions(ids: Set<UUID>)
```

или repository read model, который сразу возвращает данные для Catalog.

Не протаскивать SwiftData records в UI.

### Effort

M

---

## PF-03 — HIGH — Recipe details делает примерно 2N–3N lookup на ingredients

**Тип:** performance / service complexity  
**Приоритет:** 8  
**Статус:** TODO

### Где

`RecipeService.swift`

Особенно:
- `details()`
- `ingredientReadModels`
- `outdatedIngredientCount`
- `calculation(for:)`

### Проблема

Для каждого ingredient отдельно загружаются:
- ProductVersion;
- Product;
- затем Product может снова загружаться для outdated check;
- calculation снова может fetch-ить version.

### Target

На один Recipe operation:

1. собрать `Set<Product.ID>`;
2. собрать `Set<ProductVersion.ID>`;
3. batch fetch;
4. построить:
   - `productsByID`;
   - `versionsByID`;
5. на этих данных:
   - построить read models;
   - определить outdated ingredients;
   - выполнить calculation.

### Benefit

- меньше SwiftData calls;
- короче `RecipeService`;
- единая согласованная snapshot выборка.

### Effort

M

---

## PF-04 — HIGH — Recipe preview пересчитывает composition при изменении output amount

**Тип:** performance / state design  
**Приоритет:** 9  
**Статус:** TODO

### Где

- `RecipeViews.swift`, примерно 461–469
- `RecipeEditorViewModel.refreshPreview()`
- `RecipeService.preview`

### Проблема

При каждом изменении:

```text
cookedWeightText
servingsCountText
```

запускается полный preview calculation, включая повторное разрешение ingredient versions.

Но изменение cooked weight / servings count не изменяет total nutrition ингредиентов.

### Target

Разделить:

```text
ingredient composition changed
→ пересчитать ingredient total

output changed
→ только derived per-unit preview
```

Дополнительно сделать preview task cancellable.

### Effort

M

---

## AR-01 — HIGH — RecipeEditor navigation/state слишком раздут

**Тип:** architecture / maintainability  
**Приоритет:** 10  
**Статус:** TODO

### Где

`RecipeViews.swift`, около 965 строк.

`RecipeEditorView` содержит state вроде:

```text
showsIngredientSelection
selectedIngredientProduct
selectedIngredientRecipe
showsIngredientProductCreation
showsIngredientRecipeCreation
editingIngredient
focusedField
```

и несколько параллельных `navigationDestination`.

### Проблема

Фактически navigation state machine выражена набором независимых Bool/Optional.

Это повышает риск невозможных комбинаций state и усложняет дальнейшие изменения.

### Target

Локальный typed route для Recipe Editor.

Conceptually:

```swift
enum RecipeEditorRoute {
    case ingredientCatalog
    case productAmount(...)
    case recipeAmount(...)
    case editIngredient(...)
    case newProduct
    case newRecipe
}
```

Не вводить global Coordinator framework.

### Важно

На этом шаге не менять визуальный дизайн Recipe editor.

### Effort

M–L

---

## AR-02 — HIGH — `RecipeViews.swift` слишком большой

**Тип:** source organization  
**Приоритет:** 11  
**Статус:** TODO

### Где

`RecipeViews.swift` ≈ 965 строк.

### Target

После стабилизации typed navigation физически разделить на:

```text
RecipeListView.swift
RecipeDetailView.swift
RecipeEditorView.swift
RecipeAmountViews.swift
RecipeVersionHistoryView.swift
```

### Почему после AR-01

Просто разрезать большой файл без упрощения state даст пять файлов со всё тем же spaghetti.

### Effort

S после AR-01

---

## LC-01 — MEDIUM — Duplicate initial loads (`.task` + `.onAppear`)

**Тип:** lifecycle / unnecessary work  
**Приоритет:** 12  
**Статус:** TODO

### Где

Найдены как минимум:

- Today
- Product list
- Recipe list
- Recipe detail

### Проблема

Один экран может вызывать `load()` дважды при первом appearance.

### Target

Один lifecycle owner.

Предпочтительно SwiftUI `.task` / `.task(id:)`, если нет причины использовать `onAppear`.

### Effort

S

---

## LC-02 — MEDIUM — Search запускает независимый Task на каждый символ

**Тип:** async lifecycle  
**Приоритет:** 13  
**Статус:** TODO

### Где

Catalog/search views.

### Проблема

Pattern:

```swift
.onChange(of: searchText) {
    Task { await model.load(...) }
}
```

Старый search task может завершиться после нового и показать stale results.

### Target

Использовать cancellable lifecycle:

```swift
.task(id: searchText)
```

Debounce добавлять только при реальной необходимости.

### Effort

S

---

## SH-01 — MEDIUM — Shared UI физически разбросан по feature files

**Тип:** maintainability / reuse organization  
**Приоритет:** 14  
**Статус:** TODO

### Уже реально shared

- `AmountEditorView`
- `FoodCompositionSection`
- `FoodCompositionEntryRow`
- `FoodCompositionAddRow`

### Проблема

Они живут внутри feature-specific файлов (`DiaryAmountView.swift`, `TodayView.swift`), хотя используются несколькими flows.

### Target

Без изменения behavior переместить в:

```text
Shared/UI/
```

### Важно

Это только physical/source organization refactor.

Не менять API компонентов, если это не нужно.

### Effort

S

---

## SH-02 — MEDIUM — Несколько одинаковых InlineErrorView

**Тип:** duplication  
**Приоритет:** 15  
**Статус:** TODO

### Проблема

Есть несколько feature-specific variants:

```text
InlineErrorView
DiaryInlineErrorView
GoalInlineErrorView
StatisticsInlineErrorView
```

### Target

Если визуальный контракт действительно одинаков:
- оставить один `Shared/UI/InlineErrorView`.

Если есть реальные различия:
- не объединять искусственно.

### Effort

XS–S

---

## SH-03 — MEDIUM — Number parsing/formatting duplicated

**Тип:** duplication / consistency  
**Приоритет:** 16  
**Статус:** TODO

### Где

Product, Recipe, Today/Amount и другие numeric forms.

### Проблема

Повторяются:
- parsing decimal input;
- display formatting;
- zero/empty handling;
- locale-ish преобразования.

### Target

Небольшой `Shared/Formatting/NumberFormatting.swift`.

Не создавать большой formatting framework.

### Effort

S–M

---

## CL-01 — MEDIUM — Dead / obsolete code

**Тип:** cleanup  
**Приоритет:** 17  
**Статус:** TODO

### Safe / very likely safe candidates

`Features/RootPlaceholderViews.swift`

Содержит старые:
- `StatisticsPlaceholderView`
- `TodayPlaceholderView`
- `CatalogPlaceholderView`

### Legacy selection

- `DiaryService.FoodSelectionItem`
- `DiaryService.foodSources(matching:)`

Shared Catalog уже заменил старый food selection flow.

### Likely dead

- `TodayViewModel.reorder(...)`
- `DiaryService.reorder(...)`
- `RecipeEditorViewModel.removeIngredients(at:)`
- `RecipeEditorViewModel.draft(for:)`

### Routes requiring verification

- `TodayRoute.productDetails`
- `TodayRoute.recipeDetails`

`recipeDetails` содержит placeholder «Этот экран пока недоступен».

### Rule

Перед удалением каждого кандидата:
- полный reference search;
- проверить previews/conditional compilation;
- не удалять всё одним blind cleanup.

### Effort

S

---

## UI-01 — MEDIUM — Recipe Editor всё ещё имеет keyboard `Готово`

**Тип:** UI consistency  
**Приоритет:** 18  
**Статус:** TODO

### Где

`RecipeViews.swift`, примерно 451–456.

### Проблема

Recipe Editor использует:

```swift
ToolbarItemGroup(placement: .keyboard)
Button("Готово")
```

В Product Editor этот keyboard accessory уже специально убран.

### Target

Тот же focus contract:

```text
input focused
→ keyboard visible

focus nil
→ keyboard hidden
```

Без custom/system toolbar button `Готово`.

### Effort

XS–S

---

## UI-02 — MEDIUM — Goals editor слишком плотный

**Тип:** UX redesign  
**Приоритет:** 19  
**Статус:** REVIEW LATER

### Current

```text
7 дней × 4 numeric fields = 28 inputs
```

### Potential improvement

Рассмотреть более компактное редактирование:
- day selector + one-day editor;
- copy to all;
- либо disclosure/grouped sections.

### Важно

Это design change, а не technical refactor.

Сначала завершить correctness/performance работу.

### Effort

M

---

## UI-03 — MEDIUM — Проверить consistency Catalog quick-action placement

**Тип:** UX / docs divergence  
**Приоритет:** 20  
**Статус:** DECISION LATER

### Divergence

Docs описывают quick-action area:

```text
[ Сканировать ] [ Добавить ]
```

а current native code использует часть actions в toolbar.

### Decision

Если current toolbar UX нравится и хорошо работает:
- обновить spec/architecture.

Если хотим product-spec layout:
- сделать отдельный UI task.

Не рефакторить случайно в рамках architecture cleanup.

---

## UI-04 — LOW — Standard native back vs `< < <`

**Тип:** visual/product decision  
**Приоритет:** 21  
**Статус:** DECISION LATER

Docs требуют `< < <`.

Current native UI использует стандартный iOS back chevron в части flows.

Это чистая design decision.

Не блокирует refactor.

---

## UI-05 — LOW — Recipe create/edit push vs focused full-screen

**Тип:** navigation/product decision  
**Приоритет:** 22  
**Статус:** DECISION LATER

Docs описывают focused full-screen Recipe create/edit.

Current implementation использует normal `NavigationStack` push.

Если UX current flow устраивает:
- вероятно проще обновить architecture/spec.

Если хотим focused flow:
- делать отдельным navigation task после AR-01.

---

## AX-01 — LOW — Accessibility manual audit

**Тип:** accessibility  
**Приоритет:** 23  
**Статус:** TODO LATER

### Already good

- icon-only actions в основном имеют accessibility labels;
- touch targets в ключевых местах близки/соответствуют 44pt;
- trash action семантически подписан.

### Проверить на physical iPhone

- Dynamic Type;
- Amount input width;
- long source names;
- Recipe selection row labels;
- VoiceOver order;
- macro preview;
- truncated text.

### Effort

S–M manual pass

---

## CFG-01 — LOW — `SWIFT_VERSION` расходится с architecture docs

**Тип:** project configuration  
**Приоритет:** 24  
**Статус:** TODO

### Current project

```text
SWIFT_VERSION = 5.0
IPHONEOS_DEPLOYMENT_TARGET = 17.0
```

Docs говорят Swift 5.9+.

### Target

Проверить фактический Xcode language mode и привести project/docs к одному утверждению.

### Effort

XS

---

## KF-01 — LOW / HIGH RISK — Focus restoration логика находится в `AppRouter`

**Тип:** architecture debt  
**Приоритет:** 25  
**Статус:** DEFER

### Current

`AppRouter` содержит Amount-specific state:

```text
amountFocusRestorationRevision
```

Product editor increment-ит revision, Amount screen его наблюдает и восстанавливает focus/select-all.

### Почему это architectural smell

Global router знает lifecycle конкретного keyboard/input flow.

### Почему НЕ надо исправлять сейчас

Эта зона уже проходила через несколько regressions на physical iPhone.

Текущий mechanism появился после реальной отладки и работает.

### Recommendation

1. оставить;
2. убрать diagnostic noise после периода стабильности;
3. только потом отдельным task попробовать локализовать focus restoration внутри Amount feature;
4. обязательно physical iPhone regression.

### Effort

M, high risk

---

## KF-02 — LOW — Diagnostic keyboard logging

**Тип:** cleanup  
**Приоритет:** 26  
**Статус:** DEFER UNTIL STABLE

После подтверждённой стабильности keyboard return flow:
- удалить лишний `OSLog`, либо
- оставить только полезные DEBUG-only logs.

Не делать одновременно с focus refactor.

### Effort

XS

---

# 3. Что НЕ рефакторить

Следующие части признаны сильными и должны остаться архитектурной опорой.

## KEEP-01 — `LocalDay`

Не заменять на persisted `Date`.

## KEEP-02 — Immutable ProductVersion

Не создавать generic mutable Product persistence.

## KEEP-03 — Immutable RecipeVersion

Composition history должна оставаться immutable.

## KEEP-04 — RecipeIngredient pins ProductVersion

Никогда не заменять на dynamic `Product.currentVersionID`.

## KEEP-05 — Diary snapshots

Не пересчитывать исторические entries автоматически.

## KEEP-06 — Narrow Diary commands

Оставить отдельные:
- create;
- update amount/unit;
- move/reorder;
- soft delete.

Не вводить generic `updateDiaryEntry`.

## KEEP-07 — Repository boundary

Feature Views не должны получать `ModelContext` / `@Query`.

## KEEP-08 — SwiftData VersionedSchema / MigrationPlan

Не считать это premature abstraction.

## KEEP-09 — Shared Catalog

Текущий `CatalogView` действительно используется management/selection flows.

Не создавать отдельные копии Catalog.

## KEEP-10 — Shared Amount UI

Не создавать отдельные lookalike Amount screens для Diary/Recipe.

## KEEP-11 — Shared FoodComposition visuals

Оставить одну visual implementation для Diary meals и Recipe ingredients.

## KEEP-12 — Today gesture implementation

Не переписывать просто потому, что custom/native alternative выглядит красивее в коде.

Главный критерий — physical iPhone reliability.

---

# 4. Recommended phases

После выполнения первых correctness items двигаться фазами.

## Phase C — Correctness first

1. CT-01 Catalog calories
2. CT-02 Recipe multi-unit decision + implementation
3. CT-03 serving default
4. CT-04 quick-add concurrency
5. CT-05 safe navigation pop

## Phase P — Persistence / performance

6. PF-01 targeted Diary SwiftData queries
7. PF-02 batch Catalog current versions
8. PF-03 batch Recipe dependencies
9. PF-04 Recipe preview calculation lifecycle

## Phase A — Architecture simplification

10. AR-01 Recipe typed navigation/state
11. AR-02 split Recipe source files
12. LC-01 duplicate loads
13. LC-02 cancellable search

## Phase S — Shared cleanup

14. SH-01 shared UI placement
15. SH-02 InlineError consolidation
16. SH-03 number formatting
17. CL-01 dead code cleanup

## Phase U — UI polish

18. UI-01 Recipe keyboard
19. UI-02 Goals redesign review
20. UI-03 Catalog action placement decision
21. UI-04 Back style decision
22. UI-05 Recipe full-screen decision
23. AX-01 accessibility pass

## Phase D — Deferred/risky cleanup

24. CFG-01 Swift language mode
25. KF-02 logging cleanup
26. KF-01 focus architecture, только если действительно нужно

---

# 5. Самые ценные quick wins

После первых correctness fixes:

1. Safe route-aware pop.
2. Duplicate `.task` / `.onAppear` load cleanup.
3. Search cancellation через `.task(id:)`.
4. Disable concurrent quick-add.
5. Recipe keyboard `Готово` removal.
6. Remove old placeholder views.
7. Remove confirmed dead food-selection code.
8. Shared InlineError.
9. Shared number formatting.
10. Move already-shared UI primitives в `Shared/UI`.

---

# 6. Самые опасные giant-refactor идеи, которые НЕ делать

## Не делать один commit:

```text
Recipe navigation rewrite
+
Recipe visual redesign
+
keyboard changes
+
SwiftData optimization
```

## Не переписывать:

```text
DiaryService
→ generic CRUD
```

Это ослабит historical integrity.

## Не менять вместе:

```text
SwiftData schema
+
repository refactor
+
UI
```

## Не возвращаться к Today gesture experiments без реального bug report.

## Не заменять работающий FocusState workaround на «более красивый» без отдельного physical-iPhone test cycle.

---

# 7. Итоговая оценка проекта

Проект не нуждается в переписывании.

Сильные стороны:
- историческая модель;
- versioning;
- domain separation;
- repository boundary;
- typed domain values;
- shared Catalog;
- shared Amount UI;
- shared food composition UI.

Основной technical debt сосредоточен в:
1. SwiftData query efficiency;
2. N+1 access patterns;
3. Recipe feature complexity;
4. async/lifecycle duplication;
5. накопившихся obsolete helpers;
6. keyboard-specific glue.

Основные product/UI риски:
1. calories в Catalog могут не соответствовать отображаемому amount;
2. Recipe multi-unit support не полностью доступен пользователю;
3. `100` как fallback для `serving`;
4. Recipe keyboard UX отличается от Product Editor.

---

# 8. Точка старта

Начинать с:

## CT-01 — Catalog calories must match displayed amount

До завершения CT-01 не переходить к следующему пункту.

После каждого выполненного пункта:
- обновлять его `Статус`;
- фиксировать краткий результат;
- переходить ровно к следующему согласованному item.
