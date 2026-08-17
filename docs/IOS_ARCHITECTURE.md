# Native iOS architecture and data design

**Status:** Phase iOS 0 design only  
**Scope:** a separate Swift / SwiftUI client for the existing product; no Xcode project, screens, sync implementation, or web changes are part of this document.

`PRODUCT_SPEC.md` is the authority for intended product behaviour. The existing React/Dexie application is the reference for rules, stored fields, and currently implemented behaviour.

## Target Platform

| Concern | Decision |
| --- | --- |
| Language and UI | Swift 5.9+, SwiftUI; do not make UIKit the UI architecture. |
| Minimum OS | **iOS 17.0**. |
| Navigation | `TabView`, with one independent `NavigationStack` per tab. |
| Local persistence | SwiftData, in a single local model container. |
| Concurrency | `async`/`await`, `@MainActor` UI and SwiftData boundary; no Combine dependency. |
| Device data | Local-first and usable offline; no sign-in in native v1. |
| Native camera seam | A future SwiftUI wrapper around VisionKit/AVFoundation, isolated behind `BarcodeService`. |

The native application is a new client of the same product. The React application remains intact as the web/desktop reference and possible future Supabase client.

## Current architecture understood

The web application already follows the useful separation to retain:

```text
React feature/UI
        ↓
application services
        ↓
domain rules and repository protocols
        ↓
Dexie repository implementations
        ↓
IndexedDB
```

The stores are `products`, `productVersions`, `recipes`, `recipeVersions`, `diaryEntries`, and `weeklyGoals`. Product and recipe versions are append-only. A `DiaryEntry` stores a version reference plus its own nutrition and name snapshots. It therefore does not change if the referenced product or recipe later changes. The services centralise nutrition calculation, date-effective goals, product/recipe versioning, barcode lookup, and diary order.

### Observed implementation/spec differences

These are not changes requested in this phase. Native behaviour follows the spec where a difference exists.

| Topic | Current web implementation | Current spec / native decision |
| --- | --- | --- |
| New product amount | The React form initialises `baseAmount` to `100`. | The spec requires visually empty amount and nutrition inputs on create. iOS should use an optional form field until validation, then require a positive amount. |
| Diary update service | `UpdateDiaryEntryDraft` accepts `mealType`, and `DiaryService.updateEntry` can change it. The current edit UI happens to pass the existing meal. | The spec permits editing only amount and unit. iOS `updateEntryAmount` must not accept date or meal type; moving an entry is a separate `moveEntry` command. |
| Meal raw value | React persists `snack`; the Phase 0 prompt calls the case `snacks`. | Use persisted raw value **`snack`** for import compatibility and the UI label `Перекусы`. It is an intentional compatibility choice, not a translated persistent value. |
| Recipe ingredients | React stores ingredients as an array embedded in a `RecipeVersion` record. | iOS uses child SwiftData records and future Postgres rows. They remain owned by, and immutable with, their recipe version. |
| Sync metadata | Dexie contains timestamps and soft deletes where appropriate, but no sync queue/state. | iOS v1 has no sync. A later local-only metadata store will record pending/synced/failed state without adding it to cloud domain rows. |

The UI currently has no visible Recent section despite the service retaining recent-source helpers, so this is not a user-facing parity requirement.

## Architecture

```text
SwiftUI Views
    ↓ intents, loading/error state
@MainActor ViewModels
    ↓ commands and read models
Application Services
    ↓ domain values, calculators, repository protocols
Domain
    ↓
Repository implementations
    ↓                         ↓ (future)
SwiftData local store       Supabase sync transport
```

### Layer responsibilities

- **SwiftUI Views** render state and send user intents. They do not fetch SwiftData directly, calculate nutrition, decide whether to create a version, or merge sync changes. `@Query` is deliberately not used in feature views because it would bypass the repository boundary.
- **ViewModels** are `@Observable @MainActor` feature types. They own transient text input, loading, errors, selected tab/route, and call application services. They map domain errors to human language in the UI layer.
- **Application Services** coordinate one user action and its transaction: validation, resolving the required version, calculation, version creation, persistence, and later marking sync metadata. They return immutable value-type read models/commands rather than SwiftData objects.
- **Domain** contains `Nutrition`, `LocalDay`, persistent-ID-safe enums, unit resolution, nutrition and recipe calculation, validation rules, and repository protocols. It has no SwiftUI, SwiftData, VisionKit, or Supabase imports.
- **Data** contains the SwiftData record classes, mapping to/from domain values, repository implementations, and (later) sync DTOs and a sync-state store.

This is deliberately one app target and a small number of folders, not separate Swift packages. Extraction into packages is unnecessary until a second client genuinely needs it.

### Composition root and concurrency

`AppDependencies` is the one composition root. It creates one `ModelContainer`, the SwiftData repository implementations, pure calculators, and application services. Views receive a feature ViewModel with only the services it needs, normally through initializer injection or a scoped environment dependency.

SwiftData's UI-owned `ModelContext` and all repository mutations are isolated to `@MainActor`. This is appropriate for a small, single-user, local app and avoids passing model objects across actors. Repository and service APIs are still `async throws`, so a caller never assumes synchronous disk access and a later remote implementation can satisfy the same ports. Domain values, commands, and read models are `Sendable` value types. Pure calculators are nonisolated.

Network work in a future `SyncService` belongs in an actor. It passes `Codable` DTOs and IDs across actors, then asks the `@MainActor` local repository to apply a merge. No Combine is needed: SwiftUI observation plus structured concurrency is sufficient.

## Project Structure

```text
CaloriesTrackerIOS/                         # future separate Xcode project root
  App/
    CaloriesTrackerApp.swift
    AppDependencies.swift
    AppRouter.swift
    AppTab.swift
    PersistenceConfiguration.swift

  Domain/
    Core/
      Nutrition.swift
      LocalDay.swift
      PersistentEnums.swift
      DomainError.swift
    Units/
      FoodUnit.swift
      UnitConverter.swift
    Products/
      Product.swift
      ProductVersion.swift
      ServingUnit.swift
    Recipes/
      Recipe.swift
      RecipeVersion.swift
      RecipeIngredient.swift
      RecipeCalculator.swift
    Diary/
      DiaryEntry.swift
      DiaryCommands.swift
    Goals/
      WeeklyGoal.swift
      DailyMacroGoal.swift
    Statistics/
      Statistics.swift
    Repositories/
      ProductRepository.swift
      RecipeRepository.swift
      DiaryRepository.swift
      GoalRepository.swift

  Application/
    Products/ProductService.swift
    Products/BarcodeService.swift
    Recipes/RecipeService.swift
    Diary/DiaryService.swift
    Goals/GoalService.swift
    Statistics/StatisticsService.swift
    Sync/SyncService.swift                  # protocol/placeholders only until sync phase

  Data/
    SwiftData/
      SchemaV1.swift
      Models/
      Mappers/
      SwiftDataProductRepository.swift
      SwiftDataRecipeRepository.swift
      SwiftDataDiaryRepository.swift
      SwiftDataGoalRepository.swift
    Sync/                                   # future DTOs, outbox metadata, transport

  Features/
    Today/
      TodayViewModel.swift
      FoodSelectionViewModel.swift
      AmountViewModel.swift
    Statistics/
    Catalog/                                # Products and Recipes management mode
    Goals/
    Barcode/

  Shared/
    UI/
    Formatting/
    Validation/
```

`Catalog` is one feature for the management tab while Products and Recipes remain separate domain and service concerns. The diary food-selection flow remains under `Today`; it must not accidentally inherit management-mode navigation or filters.

## Navigation

### Root tabs

The tab bar has three items in the current product order: **Статистика**, **Сегодня**, **Продукты**. `Сегодня` is selected on launch even though it is visually the middle tab.

```swift
enum AppTab: Hashable {
    case statistics
    case today
    case catalog
}
```

Each tab owns an independent `NavigationPath`; switching tabs preserves its navigation state. Goals is a Statistics destination, not a tab.

```text
TabView(selection: selectedTab)
├─ Statistics: NavigationStack(path: statisticsPath)
├─ Today:      NavigationStack(path: todayPath)
└─ Products:   NavigationStack(path: catalogPath)
```

### Typed destinations

Routes are in-memory values, never internal URL strings. IDs and context are enough to re-fetch current domain data after an app state refresh.

```swift
struct DiaryContext: Hashable, Sendable {
    let day: LocalDay
    let meal: MealType
}

enum TodayRoute: Hashable {
    case foodSelection(DiaryContext)
    case amount(context: DiaryContext, source: FoodSourceReference)
    case entryEditor(DiaryEntry.ID)
    case productEditor(context: DiaryContext?, prefilledBarcode: String?)
    case productDetails(Product.ID)
    case recipeDetails(Recipe.ID)
}

enum StatisticsRoute: Hashable { case goals }

enum CatalogRoute: Hashable {
    case product(Product.ID)
    case productEditor(Product.ID?)
    case productVersionHistory(Product.ID)
    case recipe(Recipe.ID)
}
```

`FoodSourceReference` is `{ sourceType, sourceID }`, not a captured SwiftData model. Adding food resolves the source's current version at the final `DiaryService.add…` command, so the source cannot be silently stale.

The Today flow is therefore:

```text
Today(day) → Food selection(context) → Amount(context, product/recipe)
           → DiaryService.add… → replace path with Today(day)
```

The successful add removes the completed selection and amount routes, so Back does not reveal a completed form. Entry editing is pushed from Today and receives only an entry ID; it may save only its amount and unit. Reorder/meal moves invoke a distinct command from the diary list.

Barcode scanning and recipe create/edit are focused `fullScreenCover` flows above the relevant stack, so the tab bar is absent. Their input and completion are typed contexts/callbacks: a known barcode returns a product ID, an unknown barcode returns a prefilled barcode plus any originating `DiaryContext`. The scanner does not navigate directly to product UI.

External deep links are deferred. If introduced later, they map at the App boundary to `AppTab` plus typed route values; the feature navigation itself remains URL-free.

### Native UI principles

Use natural iOS components while preserving behaviour: `TabView`, `NavigationStack`, `List` for catalog and diary data, `Form` for editors, `TextField` with `.decimalPad`, `Picker` for units, `Toolbar`, and `swipeActions` for the explicit destructive Diary delete action. A long-press reorder/move interaction must preserve `sortOrder` and only change meal/order. Native sheets/full-screen covers are appropriate for focused scanner and recipe-editor flows, not the core food logging flow.

Touch targets, keyboard avoidance, safe-area-aware primary actions, concise contextual titles, and human-readable validation errors are product requirements. The app should not reproduce web layout or browser controls pixel-for-pixel.

## Domain Models

### Stable identifiers and values

Every synchronisable entity has an app-generated `UUID` primary ID. No database-generated integer is a domain identity. Version IDs, ingredient IDs, serving-unit IDs, and child daily-goal IDs are UUIDs too, which makes an offline object valid before it reaches a server.

```swift
struct Nutrition: Hashable, Codable, Sendable {
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double

    static let zero = Self(calories: 0, protein: 0, fat: 0, carbs: 0)
    func scaled(by factor: Double) -> Self { /* one four-field implementation */ }
    func adding(_ other: Self) -> Self { /* one four-field implementation */ }
}
```

`Nutrition` is the domain value type. SwiftData records store its four scalar values for sortable/queryable persistence and straightforward Postgres mapping. Views receive formatted `Nutrition` or read models but never repeat its formulas. Values are stored unrounded as `Double`; formatting rounds only for display.

```swift
enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    var russianLabel: LocalizedStringResource { /* Завтрак, Обед, Ужин, Перекусы */ }
}

enum SourceType: String, Codable, Sendable { case product, recipe }
enum ProductBaseUnit: String, Codable, CaseIterable, Sendable { case g, ml, piece, serving }
enum ServingConversionUnit: String, Codable, Sendable { case g, ml, piece }
```

The raw values are persistence/API values only. UI labels live in localisation/formatting. `barcode` is an opaque `String?`; normalisation is trim-to-nil only, never numeric parsing, so leading zeros survive.

### Products and historical serving units

```text
Product (logical identity)
  id, name, barcode?, currentVersionID, createdAt, updatedAt, deletedAt?
                │
                └── ProductVersion (immutable)
                    id, productID, versionNumber, baseUnit, baseAmount,
                    Nutrition, createdAt
                    └── ServingUnit[] (immutable children)
```

`ProductVersion` additionally has a future-sync `basedOnVersionID?`: nil for v1, otherwise the version that was current when this version was authored. It does not affect nutrition and makes a concurrent-version conflict observable. A version's nutrition, base unit, base amount, and serving-unit collection are never edited.

`ServingUnit` is preserved even though the first native product editor will not create or edit them. It has `id`, `productVersionID`, `position`, `name`, `conversionAmount`, and `conversionUnit`. It can represent `1 кусок = 32 г` or `1 стакан = 250 мл`. A base `serving` product cannot have conversion units, matching the web validation.

The persisted diary/ingredient unit token is compatible with the web format:

| Situation | Persisted token |
| --- | --- |
| Product base unit | `g`, `ml`, `piece`, or `serving` |
| Historical product serving unit | `serving:<ServingUnit UUID>` |
| Recipe by cooked weight | `g` |
| Recipe by servings | `piece` |

`UnitConverter` validates a selected token against the referenced **version**, then converts a serving amount to that version's base amount. It does not calculate nutrition.

`NutritionCalculator` takes a `ProductVersion`, a base-normalised amount, and returns `version.nutrition × normalizedAmount / baseAmount`. It rejects non-finite values, a non-positive base amount, or a negative amount. The service requires a strictly positive user-entered diary/ingredient amount even though the calculator itself can represent zero.

### Recipes

```text
Recipe (logical identity)
  id, name, currentVersionID, createdAt, updatedAt, deletedAt?
                │
                └── RecipeVersion (immutable)
                    id, recipeID, versionNumber, totals, cookedWeight?, servingsCount?, createdAt
                    └── RecipeIngredient[] (immutable children)
                         productID + pinned productVersionID + amount + unit + normalizedAmount
```

An ingredient resolves nutrition from its pinned `productVersionID`, never from `Product.currentVersionID`. `normalizedAmount` is stored as an audit/value convenience: it records the amount in the product version's base unit that was used when the recipe version was made. The service validates that the pinned product version belongs to `productID`.

`RecipeCalculator` is the only recipe calculation path:

1. resolve every ingredient's unit against its pinned product version;
2. calculate every ingredient's nutrition through `NutritionCalculator`;
3. sum to immutable total nutrition;
4. derive per-100-g nutrition as `total × 100 / cookedWeight` when supplied;
5. derive per-serving nutrition as `total / servingsCount` when supplied.

A valid recipe has a non-empty name, at least one ingredient, and at least one of `cookedWeight` or `servingsCount`. Changing name alone updates the logical recipe's metadata; changing composition, pinned version, amount, unit, cooked weight, servings count, or derived totals appends a new recipe version.

### Diary

```text
DiaryEntry
  id, localDay, mealType, sortOrder,
  sourceType, sourceID, sourceVersionID, sourceName,
  amount, unit,
  Nutrition snapshot,
  createdAt, updatedAt, deletedAt?
```

`sourceName` and `Nutrition` are mandatory snapshots. `sourceType` disambiguates the two UUID namespaces. `sortOrder` is a finite integer-like `Int` scoped to `(localDay, mealType)` and is initially allocated with gaps (0, 100, 200 …); the move service normalises the affected meals in one write.

The key commands are intentionally narrow:

```swift
struct CreateDiaryEntryCommand: Sendable {
    let context: DiaryContext
    let source: FoodSourceReference
    let amount: Double
    let unitToken: String
}

struct UpdateDiaryEntryAmountCommand: Sendable {
    let entryID: UUID
    let amount: Double
    let unitToken: String
}

struct MoveDiaryEntryCommand: Sendable {
    let entryID: UUID
    let targetMeal: MealType
    let targetIndex: Int
}
```

There is no general DiaryEntry update command. In particular, amount editing loads exactly `entry.sourceVersionID`, resolves its unit there, recalculates its snapshot from that historic version, and preserves `localDay`, `mealType`, source IDs, source name, and sort order. Moving preserves source, amount, unit, and snapshot; it changes only `mealType`, `sortOrder`, and `updatedAt`.

### Goals and statistics

`DailyMacroGoal` is a `Nutrition`-shaped value with the same four non-negative fields. `WeeklyGoal` is immutable and has `effectiveFrom: LocalDay` plus exactly seven weekday-specific daily goals (`monday` … `sunday`). A new setting is a new weekly-goal identity rather than an update to the previous record.

`GoalService.goal(for:)` chooses the non-deleted/non-superseded weekly goal with greatest `effectiveFrom <= diary day`, then uses the weekday calculated from that `LocalDay`. No goal snapshot is copied into a diary entry; historical reporting remains correct because goals themselves are historical immutable records.

Statistics has no persistent entity. `StatisticsService` aggregates non-deleted diary nutrition snapshots and resolves historical goals. It computes macro-energy proportions with `P × 4`, `F × 9`, and `C × 4`; diary calories remain their independent snapshot. A current week excludes future days from its calorie balance, while a completed past week uses all seven days.

## Date Handling

`Date` is not a diary day. A diary day is a local civil calendar date, represented in domain code as an opaque canonical `LocalDay` and persisted as its `yyyy-MM-dd` key.

```swift
struct LocalDay: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    let rawValue: String // validated, zero-padded Gregorian YYYY-MM-DD
}
```

- `DiaryEntryRecord.dayKey` and `WeeklyGoalRecord.effectiveFromKey` store the raw key, never midnight `Date` values.
- Parsing validates real Gregorian calendar components. Adding/subtracting a day and getting the weekday use `Calendar(identifier: .gregorian)` with `DateComponents(year:month:day:)`, not `ISO8601DateFormatter` or an implicit UTC conversion.
- UI conversion to `Date` for a date picker/formatter is explicitly at local noon in the user's calendar, and conversion back immediately produces `LocalDay`. That presentation `Date` is never persisted as the diary day.
- `createdAt`, `updatedAt`, `deletedAt`, and sync cursors are absolute `Date` instants. They map to UTC `timestamptz` in Postgres.

Thus the stored key `2026-08-14` remains that calendar day regardless of device time zone, travel, daylight-saving changes, or server time zone.

## SwiftData Models

### General conventions

Persistence classes have a `Record` suffix; domain values do not. Every record below has `@Attribute(.unique) var id: UUID`. Scalar enum values are persisted as `String` raw values (`mealTypeRaw`, `sourceTypeRaw`, `baseUnitRaw`) even though SwiftData can encode enums. This is explicit, migration-friendly, and maps directly to Postgres check constraints.

`@Attribute(.unique)` is used for stable primary IDs and the one-device `WeeklyGoalRecord.effectiveFromKey`. SwiftData v1 should not depend on a composite unique constraint or a partial unique index. Repository validation enforces product barcode uniqueness, including soft-deleted products, before saving. Future Postgres supplies the stronger `(user_id, barcode) WHERE barcode IS NOT NULL` partial unique index.

For the personal data volume expected in v1, use `FetchDescriptor` predicates/sorts rather than premature index work. If the deployed iOS 17 SDK supports the required stable index macro at implementation time, add only the indicated secondary indexes after measuring; correctness does not rely on them.

### Record schema

The following is the exact logical SwiftData schema (initialiser boilerplate omitted).

| `@Model` | Stored fields | Unique / useful query keys |
| --- | --- | --- |
| `ProductRecord` | `id`, `name`, `barcode?`, `currentVersionID`, `createdAt`, `updatedAt`, `deletedAt?` | `id`; fetch active products by `deletedAt`, search name/barcode, resolve `currentVersionID`. |
| `ProductVersionRecord` | `id`, `productID`, `basedOnVersionID?`, `versionNumber`, `baseUnitRaw`, `baseAmount`, `calories`, `protein`, `fat`, `carbs`, `createdAt` | `id`; `(productID, versionNumber)` is service-unique locally; fetch versions by product. |
| `ServingUnitRecord` | `id`, `productVersionID`, `position`, `name`, `conversionAmount`, `conversionUnitRaw` | `id`; fetch/relationship by version, ordered by position. |
| `RecipeRecord` | `id`, `name`, `currentVersionID`, `createdAt`, `updatedAt`, `deletedAt?` | `id`; active/search by `deletedAt` and name. |
| `RecipeVersionRecord` | `id`, `recipeID`, `basedOnVersionID?`, `versionNumber`, four `total…` values, `cookedWeight?`, `servingsCount?`, `createdAt` | `id`; `(recipeID, versionNumber)` service-unique locally; fetch versions by recipe. |
| `RecipeIngredientRecord` | `id`, `recipeVersionID`, `position`, `productID`, `productVersionID`, `amount`, `unitToken`, `normalizedAmount` | `id`; fetch/relationship by recipe version, ordered by position. |
| `DiaryEntryRecord` | `id`, `dayKey`, `mealTypeRaw`, `sortOrder`, `sourceTypeRaw`, `sourceID`, `sourceVersionID`, `sourceName`, `amount`, `unitToken`, `calories`, `protein`, `fat`, `carbs`, `createdAt`, `updatedAt`, `deletedAt?` | `id`; query active entries by `(dayKey, mealTypeRaw, sortOrder)`, reports by `dayKey`, and sync by `updatedAt`. |
| `WeeklyGoalRecord` | `id`, `effectiveFromKey`, `createdAt` | `id`, `effectiveFromKey` (unique in a single local profile); fetch latest effective date. |
| `DailyMacroGoalRecord` | `id`, `weeklyGoalID`, `weekdayRaw`, `position`, `calories`, `protein`, `fat`, `carbs` | `id`; service enforces one of seven weekdays per weekly goal. |

All numeric values are finite; `baseAmount`, conversion amounts, ingredient amounts, cooked weight, and servings count are positive where present. Nutrition and goals are non-negative. `sourceName`, unit tokens, and enum raws are non-empty valid values.

## Relationships & Delete Rules

Relationships improve local traversal but UUID foreign-key fields remain the authoritative cross-store identity. In particular, ingredient and diary version references are IDs rather than strong object references: a logical soft delete or a future import must never invalidate history.

| Owner relationship | Inverse | Delete rule | Rationale |
| --- | --- | --- | --- |
| `ProductRecord.versions` ↔ optional `ProductVersionRecord.product` | Product version has `productID` too | `.nullify` | A physical product cleanup must not remove versions; ordinary user delete is soft only. |
| `ProductVersionRecord.servingUnits` ↔ optional `ServingUnitRecord.productVersion` | Serving unit has `productVersionID` too | `.cascade` | Units are inseparable implementation children of an immutable version. A version is never user-deleted. |
| `RecipeRecord.versions` ↔ optional `RecipeVersionRecord.recipe` | Recipe version has `recipeID` too | `.nullify` | Product-level soft/physical cleanup cannot erase recipe-version history. |
| `RecipeVersionRecord.ingredients` ↔ optional `RecipeIngredientRecord.recipeVersion` | Ingredient has `recipeVersionID` too | `.cascade` | Ingredients are inseparable children of that version. A version is never user-deleted. |
| `WeeklyGoalRecord.dailyGoals` ↔ optional `DailyMacroGoalRecord.weeklyGoal` | Child has `weeklyGoalID` too | `.cascade` | Exactly seven child records define one immutable goal. User-visible goal deletion is not in v1. |
| Diary source IDs / ingredient product IDs | none | none | They are polymorphic/historical UUID references, deliberately not cascaded relationships. |

No user action calls `ModelContext.delete` for Product, Recipe, ProductVersion, RecipeVersion, RecipeIngredient, ServingUnit, or DiaryEntry. `ProductService.softDelete`, `RecipeService.softDelete`, and `DiaryService.softDelete` set `deletedAt` (and `updatedAt` for mutable logical/diary entities). A future technical cleanup may physically delete only data proven unreferenced and safely synced; it is not a normal product feature.

### Seven child records for goals

Use `DailyMacroGoalRecord` child records rather than a transformable/codable seven-element array or seven repeated columns.

| Option | Result |
| --- | --- |
| Seven child records — **chosen** | Normalised, individually validateable, maps directly to `daily_macro_goals`, and can enforce weekday uniqueness in Postgres. Slightly more SwiftData mapping code. |
| Codable array | Concise local storage but opaque to queries/migrations and awkward to sync or constrain in Postgres. |
| Seven columns on `WeeklyGoal` | Simple local reads but repeats fields, makes weekday operations brittle, and does not map naturally to the requested cloud table. |

The service creates all seven child records in the same save as the weekly-goal record and validates the exact fixed weekday set. They are never independently edited.

## Repositories

Repository protocols expose domain values/commands, not `@Model` objects and not `ModelContext`. The abbreviated signatures below show the required surface; feature-specific read models can be added without exposing persistence.

```swift
@MainActor
protocol ProductRepository: Sendable {
    func activeProducts(matching query: String) async throws -> [Product]
    func product(id: UUID, includingDeleted: Bool) async throws -> Product?
    func product(withBarcode barcode: String) async throws -> Product?
    func version(id: UUID) async throws -> ProductVersion?
    func versions(for productID: UUID) async throws -> [ProductVersion]
    func create(_ product: Product, initialVersion: ProductVersion) async throws
    func saveLogicalMetadata(_ product: Product) async throws
    func append(_ version: ProductVersion, settingCurrentVersionOf product: Product) async throws
    func softDeleteProduct(id: UUID, at: Date) async throws
}

@MainActor
protocol RecipeRepository: Sendable {
    func activeRecipes(matching query: String) async throws -> [Recipe]
    func recipe(id: UUID, includingDeleted: Bool) async throws -> Recipe?
    func version(id: UUID) async throws -> RecipeVersion?
    func versions(for recipeID: UUID) async throws -> [RecipeVersion]
    func create(_ recipe: Recipe, initialVersion: RecipeVersion) async throws
    func saveLogicalMetadata(_ recipe: Recipe) async throws
    func append(_ version: RecipeVersion, settingCurrentVersionOf recipe: Recipe) async throws
    func softDeleteRecipe(id: UUID, at: Date) async throws
}

@MainActor
protocol DiaryRepository: Sendable {
    func entry(id: UUID, includingDeleted: Bool) async throws -> DiaryEntry?
    func entries(on day: LocalDay) async throws -> [DiaryEntry]
    func entries(in days: [LocalDay]) async throws -> [DiaryEntry]
    func create(_ entry: DiaryEntry) async throws
    func save(_ entry: DiaryEntry) async throws
    func save(_ entries: [DiaryEntry]) async throws // move/reorder transaction
    func softDeleteEntry(id: UUID, at: Date) async throws
}

@MainActor
protocol GoalRepository: Sendable {
    func goal(id: UUID) async throws -> WeeklyGoal?
    func latestGoal() async throws -> WeeklyGoal?
    func goal(effectiveOn day: LocalDay) async throws -> WeeklyGoal?
    func goals(effectiveOn days: [LocalDay]) async throws -> [LocalDay: WeeklyGoal]
    func create(_ goal: WeeklyGoal) async throws
}
```

`append(…, settingCurrentVersionOf:)`, `create(…, initialVersion:)`, diary reorders, and a later outbox mark are one local persistence transaction. The implementation validates a product/recipe version belongs to its logical parent, validates barcode uniqueness across active and deleted records, and never resolves a historic entry through a current version.

## Services

| Service | Responsibility | Must not own |
| --- | --- | --- |
| `ProductService` | Product search/details, draft validation, barcode uniqueness, create metadata, append a version only when versioned fields change, soft delete. | Diary snapshots or recipe totals. |
| `RecipeService` | Resolve and pin product versions, calculate totals, create/version recipes, identify compatible newer ingredient versions. | Product mutation or diary writes. |
| `DiaryService` | Day read model/totals, source selection, unit options, preview, create snapshot, historic amount edit, delete, and move/reorder. | Current-goal selection or statistics presentation. |
| `GoalService` | Validate seven-day goal draft, append a goal, select goal effective for a local day. | Diary aggregation. |
| `StatisticsService` | Aggregate persisted diary snapshots and historical goals for a day/week. | Persistent statistics cache or source recalculation. |
| `BarcodeService` | Normalise local code, exact local lookup, and return a neutral lookup result. | Scanner presentation or navigation. |
| `SyncService` (future) | Outbox/inbox, pull/push orchestration, merge, retry state. | UI state, nutrition calculations, or direct feature navigation. |

The preview used by Amount and the snapshot saved by `DiaryService` call the same domain calculator path. That prevents an on-screen value differing from stored nutrition.

## Historical Integrity Rules

These rules are invariants, not merely UI behaviour:

1. Product nutrition, base unit/amount, and serving units live only in immutable `ProductVersion` records. A new current version never mutates v1.
2. Recipe composition, ingredient units/amounts/pinned product versions, output quantities, and totals live only in immutable `RecipeVersion` records.
3. A `RecipeIngredient` always references a concrete `ProductVersionID`; it never follows a current product version automatically.
4. A new diary entry resolves the selected source's current version once, stores `sourceType`, `sourceID`, `sourceVersionID`, `sourceName`, amount/unit, and nutrition snapshot, then does not automatically recalculate.
5. Editing a diary amount/unit resolves exactly its saved `sourceVersionID`; it does not look up `currentVersionID`.
6. A diary move/reorder never alters its local day, source/version reference, amount/unit, source-name snapshot, or nutrition snapshot.
7. Soft deleting a product or recipe removes it from selectable/catalog results but preserves all versions, recipe ingredients, and diary snapshots.
8. Goals are selected by `effectiveFrom <= LocalDay`, so a historic diary/statistics screen does not use today's settings.

Each relevant implementation phase must include manual regression checks for these invariants, particularly Product v1 → v2 / old entry; Recipe v1 → v2 / old entry; editing an old entry after a source version changes; soft delete; historical goal resolution; and moving/reordering without changing a source, nutrition snapshot, or local day.

## Supabase-ready Schema

Sync is not part of native v1. The local design nevertheless keeps server-compatible UUIDs, scalar enum keys, normalised child records, timestamps, tombstones, and UUID references.

### Ownership and common fields

Every cloud table has `id uuid primary key` generated by the client, `user_id uuid not null references auth.users(id)`, and `created_at timestamptz not null`. Mutable logical parents (`products`, `recipes`, `diary_entries`) also have `updated_at timestamptz not null` and `deleted_at timestamptz null`. Append-only version/child rows have `created_at`; they are not ordinarily updated/deleted. `weekly_goals` is append-only, so its creation time is its effective audit timestamp; add a nullable tombstone only if a future product decision introduces goal deletion.

`LocalDay` maps to PostgreSQL `date`, while absolute `Date` maps to `timestamptz`. App/API conversion must format/parse `date` as the same `yyyy-MM-dd` civil key, never as a timestamp.

### Tables, foreign keys, and constraints

| Table | Important columns and foreign keys | Important uniqueness and indexes |
| --- | --- | --- |
| `products` | `name`, `barcode?`, `current_version_id uuid`, timestamps/tombstone. `current_version_id` is validated by service/RPC after version insert to avoid a circular create FK. | Unique partial `(user_id, barcode) WHERE barcode IS NOT NULL`, including deleted rows. Index `(user_id, deleted_at, name)` and `(user_id, updated_at)`. |
| `product_versions` | `product_id → products(id) ON DELETE RESTRICT`, `based_on_version_id → product_versions(id) RESTRICT?`, `version_number`, base unit/amount, four nutrition values. | Unique `(user_id, product_id, version_number)` after server sequence assignment; index `(user_id, product_id, created_at)`. |
| `product_serving_units` | `product_version_id → product_versions(id) ON DELETE RESTRICT`, position, name, conversion amount/unit. | Unique `(user_id, product_version_id, position)`; index by version. |
| `recipes` | `name`, `current_version_id`, timestamps/tombstone. | Index `(user_id, deleted_at, name)` and `(user_id, updated_at)`. |
| `recipe_versions` | `recipe_id → recipes(id) ON DELETE RESTRICT`, `based_on_version_id → recipe_versions(id) RESTRICT?`, version number, totals, optional cooked weight/servings. | Unique `(user_id, recipe_id, version_number)` after canonical assignment; index `(user_id, recipe_id, created_at)`. |
| `recipe_ingredients` | `recipe_version_id → recipe_versions(id) ON DELETE RESTRICT`; `product_id → products(id) RESTRICT`; `product_version_id → product_versions(id) RESTRICT`; position, amount, unit, normalised amount. | Unique `(user_id, recipe_version_id, position)`; index `(user_id, product_version_id)`. A service/trigger verifies the pinned version belongs to the stated product. |
| `diary_entries` | `day date`, `meal_type`, `sort_order`, source type/id/version/name, amount/unit, four nutrition snapshots, timestamps/tombstone. | Index `(user_id, day, deleted_at, meal_type, sort_order)`, `(user_id, source_type, source_id)`, and `(user_id, updated_at)`. |
| `weekly_goals` | `effective_from date`, created timestamp. | Unique `(user_id, effective_from)`; index `(user_id, effective_from desc)`. |
| `daily_macro_goals` | `weekly_goal_id → weekly_goals(id) ON DELETE RESTRICT`, weekday, position, four fields. | Unique `(user_id, weekly_goal_id, weekday)` and index by goal. |

`diary_entries.source_id/source_version_id` is intentionally polymorphic (`product` or `recipe`) and cannot be a normal single SQL foreign key. `source_type` plus application/RPC validation verifies the matching pair. Source versions use `ON DELETE RESTRICT` and are never user-physically-deleted, so the reference remains resolvable. A later server-side trigger/RPC may enforce the matching source type/version relationship; duplicating nullable product and recipe version columns merely to force an FK would make the shared mobile model worse.

`user_id` is repeated in dependent tables to make RLS and indexed sync queries efficient. Insertion is performed through a transaction/RPC that verifies child ownership agrees with the parent; client-provided `user_id` is not trusted.

### RLS concept

After authentication exists, enable RLS on every application table. The basic policy is `user_id = auth.uid()` for `SELECT`, `INSERT`, `UPDATE`, and `DELETE`; inserts require `WITH CHECK (user_id = auth.uid())`. Child writes also validate parent ownership through the trusted transaction/RPC. The client never uses a service-role key. There is no local `user_id` or login requirement in Phase iOS 1.

## Sync Strategy Draft

### Local metadata, not cloud state

When sync becomes an approved feature, add a separate local-only `SyncMetadataRecord` keyed by a unique `"entityType:UUID"` string. It contains `entityType`, `entityID`, `statusRaw` (`pending`, `synced`, `failed`), `lastSyncedAt?`, `lastError?`, `retryCount`, and optionally a server revision/cursor. It is not uploaded as a product/diary field and is not shown in normal product UI.

One local save changes a user record and marks its metadata pending. For multi-record commands (a new version plus parent current-version update, diary reordering, or seven-goal creation), mark every changed sync entity pending in the same local save.

### Future cycle

```text
user command
  → validate and persist locally
  → write/update local outbox metadata as pending
  → UI immediately reflects local data

app launch / foreground / network return / periodic active-app timer
  → pull remote changes since cursor
  → merge into local store transactionally
  → push pending changes in dependency order
       parents → versions → children → parent current pointer / diary / goals
  → mark accepted items synced; retain retryable failures as failed/pending
```

No realtime subscription is required for the MVP. A bounded foreground timer and lifecycle/network triggers are enough. Pull-before-push reduces avoidable conflicts; a final pull after a successful push verifies the canonical server state.

Tombstones are retained in cloud and locally until every active device has safely passed a retention horizon. Purging a tombstone before an offline device syncs would resurrect data.

## Conflict Strategy

The initial sync policy is deliberately modest and must surface, not hide, version conflicts.

- **Append-only records:** ProductVersion, RecipeVersion, serving units, recipe ingredients, and weekly goals are merged by UUID union. They do not overwrite nutrition/composition in place.
- **Logical parent metadata/current pointer:** Use deterministic last-write-wins on `(updated_at, deviceID tie-breaker)`. This applies to name, barcode, soft delete, and `current_version_id`. A later soft delete wins over an earlier non-delete. The losing version record remains history.
- **Diary entries:** Last-write-wins by `(updated_at, deviceID)` for the same entry ID. Simultaneous edits to one entry are rare; no automatic field-level merge is promised. Diary entry creates with distinct UUIDs both survive. Reorder writes can conflict, so after merging the affected day/meal, order deterministically by `sortOrder`, then `updatedAt`, then UUID and normalise on the next explicit move/save.
- **Goals:** Different effective dates union. The cloud unique `(user_id, effective_from)` exposes two independent goals for the same effective day as a conflict. Pick deterministic LWW for the effective result but retain the losing immutable record for audit/recovery until UX for resolving it exists.

### Concurrent new versions: explicit edge case

Two offline devices can both edit Product v1 and create a different local v2. UUIDs keep both immutable versions safe, but an always-unique global `versionNumber` cannot be guaranteed offline.

Recommended sync design: include `based_on_version_id`; on push, a server-side append transaction validates the base/current relationship and atomically assigns the next **canonical** display sequence. An unsynced local version number is provisional. If a competing version has arrived, the server accepts both UUID-distinct versions, assigns a distinct sequence to the later accepted one, and LWW decides which parent points at current. Only the display ordinal of an unsynced record may be reconciled; nutrition, units, ingredients, and identity never change. The UI should describe this as a version conflict if it becomes visible, rather than silently discarding either change.

This requires an approved server RPC in the future sync phase; do not attempt to solve it with a client-side `max(versionNumber) + 1` write. The same rule applies to RecipeVersion.

## Migration Strategy

### SwiftData schema evolution

Start the first implementation with explicit `SchemaV1: VersionedSchema`, a `MigrationPlan`, stable record names, and a `ModelContainer` constructed from that versioned schema. This adds little code now and avoids treating a production local store as disposable later.

- Use lightweight stages for additive optional fields and safe renames (with `originalName` when appropriate).
- Use a custom staged migration for splits/merges, such as moving an encoded collection to child records, changing a unit representation, or repairing invalid legacy data.
- Never change the meaning of a field in place. Add a new field/table, backfill, switch reads, then retire only in a later safe schema stage.
- When a real migration is introduced, carefully validate it manually with representative existing data, including soft-deleted sources and old diary/version references. Do not reset user data as a migration strategy.

### Existing web-user data

Do not implement IndexedDB → SwiftData transfer in native v1. The realistic future path is authenticated Supabase migration: add an explicit export/import capability to the web client or a signed one-time migration tool, validate its JSON against the current web schema, upload/import in dependency order, then let iPhone pull through normal sync. A standalone signed JSON import could be an alternative after an explicit backup product decision. There is no safe direct iOS access to a Safari IndexedDB database.

## Web → Native Model Mapping

This mapping preserves a future import path. Web timestamps are ISO-8601 strings; native absolute timestamps become `Date` and cloud `timestamptz`. Web local date keys remain exact strings locally and become `date` in cloud.

| React / Dexie | Native SwiftData | Future Postgres |
| --- | --- | --- |
| `products.id` | `ProductRecord.id: UUID` | `products.id uuid PK` |
| `products.name`, `barcode`, `currentVersionId` | `name`, `barcode?`, `currentVersionID` | `name`, `barcode`, `current_version_id` |
| `products.createdAt`, `updatedAt`, `deletedAt?` | same camel-case `Date` properties | `created_at`, `updated_at`, `deleted_at` |
| `productVersions.id`, `productId`, `versionNumber` | `ProductVersionRecord.id`, `productID`, `versionNumber` | `product_versions.id`, `product_id`, `version_number` |
| `baseUnitType`, `baseAmount`, nutrition scalar fields | `baseUnitRaw`, `baseAmount`, scalar nutrition | `base_unit`, `base_amount`, `calories`, `protein`, `fat`, `carbs` |
| embedded `productVersions.servingUnits[]` | `ServingUnitRecord[]` owned by the product version | `product_serving_units` rows |
| serving-unit `id`, `name`, `conversionAmount`, `conversionUnit` | same + `productVersionID`, `position` | `id`, `name`, `conversion_amount`, `conversion_unit`, FK/version position |
| `recipes.id`, `name`, `currentVersionId`, timestamps/tombstone | `RecipeRecord` equivalents | `recipes` equivalents |
| `recipeVersions` nutritional/output fields | `RecipeVersionRecord` equivalents | `recipe_versions` columns |
| embedded `recipeVersions.ingredients[]` | `RecipeIngredientRecord[]` owned by recipe version | `recipe_ingredients` rows |
| ingredient `productId`, `productVersionId`, `amount`, `unit`, `normalizedAmount` | same with `unitToken`, `position` | product/version IDs, `amount`, `unit_token`, `normalized_amount`, position |
| `diaryEntries.date` | `DiaryEntryRecord.dayKey: String` / `LocalDay` domain | `diary_entries.day date` |
| `mealType: 'breakfast'|'lunch'|'dinner'|'snack'` | `mealTypeRaw`; `MealType` | `meal_type` check/enum; retain `snack` |
| `sortOrder`, source fields, amount/unit, sourceName | same fields with ID/raw naming | snake-case equivalents |
| diary nutrition fields | scalar snapshot fields | scalar snapshot columns |
| `weeklyGoals.effectiveFrom`, `monday…sunday` embedded goals | `WeeklyGoalRecord.effectiveFromKey` + seven `DailyMacroGoalRecord`s | `weekly_goals` + `daily_macro_goals` |

`basedOnVersionID`, child positions, and future sync metadata have no current web field. They are native/future-sync additions; imports set `basedOnVersionID` to the immediately preceding version by number when safely inferable, or `nil` if it cannot be proved, and derive positions from the imported array order.

## Native Implementation Roadmap

Each phase is intentionally small enough for one focused prompt and commit. The order protects the immutable model before UI expands.

### Validation workflow

Automated test infrastructure is not a native rewrite requirement. Do not create XCTest/UI-test targets, an automated regression suite, or fixtures solely for validation unless a future task explicitly requests them.

For every implemented phase, validate with:

```text
Swift compiler
→ Xcode build
→ manual scenario checks
→ physical iPhone check where relevant
```

The manual scenario checks include the applicable historical-integrity rules above. When actual SwiftData migrations are introduced, use careful manual migration validation with representative existing data.

1. **Phase iOS 1 — project and persistence foundation.** Create the separate iOS project, `SchemaV1`, model container, domain primitives (`LocalDay`, `Nutrition`, enums), record/domain mapping, and migration-plan skeleton. No product UI yet.
2. **Phase iOS 2 — product data and catalog.** Implement product/serving-unit persistence, repository, service, native Products catalog/detail/create/edit, soft delete, barcode manual lookup seam, and product-version history. Do not expose serving-unit editing yet.
3. **Phase iOS 3 — diary core.** Implement diary persistence/service, Today default tab, local-day navigation, meal sections/totals, add-product amount flow, historic amount edit, explicit swipe delete, and stable order/reorder/move behaviour.
4. **Phase iOS 4 — goals and statistics.** Implement weekly-goal child records, Statistics tab, historical goal selection, weekly bars/balance and macro-energy calculations. Goals are reachable only from Statistics.
5. **Phase iOS 5 — recipes.** Implement recipe records/ingredients/calculator, recipe management/detail/editor, pinned product versions, historical recipe versions, and add-recipe to the Diary flow.
6. **Phase iOS 6 — barcode scanner and polish.** Add the isolated VisionKit/AVFoundation wrapper, scanner contexts for catalog and diary, unknown-barcode product creation return flow, accessibility, offline/error-state polish, and parity review.
7. **Phase iOS 7 — migration/import readiness (only after product approval).** Carefully manually validate actual SwiftData migrations and design/implement a user-consented web-data transfer route. This is not automatic in v1.
8. **Phase iOS 8 — optional Supabase sync (only after product approval).** Add authentication, server schema/RLS/RPCs, outbox/inbox, conflict UX, and manual multi-device conflict scenarios. Sync remains separate from parity work.

### PRODUCT_SPEC parity checklist

- [ ] Today is the default tab and shows a local-day diary, four meals, totals, date navigation, add actions, explicit delete, and persistent order.
- [ ] Food selection searches Products and Recipes together and retains date/meal context.
- [ ] Amount preview and save share one calculator path; historic edit resolves saved source version only.
- [ ] Products support create/search/details/edit/soft delete/barcode/current version/version history.
- [ ] Historical serving units are retained even without first-phase creation UI.
- [ ] Recipes are versioned and pin concrete ProductVersions.
- [ ] Goals are immutable, weekly, and effective for the selected historical day.
- [ ] Statistics derives data from diary snapshots and historic goals; current-week future days are excluded.
- [ ] Barcode is local-only and preserves leading zeroes.
- [ ] All ordinary local scenarios work offline after installation.
- [ ] No version or diary history changes silently after an edit, delete, or future sync.

Backup/import, Supabase sync, AI, weight/water/exercise, notifications, HealthKit, widgets, Watch, sharing, subscriptions, and App Store work are not native-v1 parity work.

## Risks / Decisions

1. **SwiftData is local-only, not a sync engine.** Keep it behind repositories. Future Supabase merging must use DTOs and local transactions rather than expose SwiftData objects to network code.
2. **Version number under offline multi-device sync needs server coordination.** UUID identity and immutable content are safe today; canonical ordinal assignment requires the later append RPC described above.
3. **Polymorphic diary source references cannot receive one simple SQL FK.** The type-plus-ID pair is validated by services/RPC and protected by never physically deleting source versions.
4. **Local `LocalDay` is intentionally a string key.** Replacing it with a `Date` would introduce time-zone regressions and make web import less reliable.
5. **Barcode uniqueness needs two layers.** The local repository validates it, while Postgres later supplies the authoritative partial unique index. Race-free cloud enforcement cannot be delegated to the UI.
6. **Goals have no current deletion product behaviour.** The chosen immutable append-only model is enough for v1. A future delete/replace feature must define whether historical reports remain unchanged before adding tombstones.

## Architecture Decisions

- **ADR-001 — Minimum platform:** iOS 17.0; use Swift, SwiftUI, SwiftData, `NavigationStack`, and `TabView`.
- **ADR-002 — Local persistence:** SwiftData is the sole Phase iOS 1 persistence implementation and sits behind repository protocols.
- **ADR-003 — Identifiers:** all synchronisable identities are client-generated `UUID`s; never use auto-increment domain IDs.
- **ADR-004 — Product versioning:** `Product` is mutable logical metadata; `ProductVersion` and its serving units are immutable append-only historical data.
- **ADR-005 — Recipe versioning:** `Recipe` is mutable logical metadata; `RecipeVersion` and its ingredients are immutable, and ingredients pin ProductVersion UUIDs.
- **ADR-006 — Diary snapshots:** `DiaryEntry` persists source type/IDs/name, amount/unit, nutrition snapshot, and sort order. Historic edits calculate from `sourceVersionID` only.
- **ADR-007 — Calendar days:** diary and goal effective dates use validated `LocalDay` `YYYY-MM-DD` keys, never timestamp dates. Audit timestamps are absolute `Date` values.
- **ADR-008 — Meal compatibility:** persist `snack` and localise it as `Перекусы`.
- **ADR-009 — Deletes:** user-visible product, recipe, and diary deletion is soft deletion; no cascade may destroy historical versions/entries.
- **ADR-010 — Goals:** store exactly seven normalised `DailyMacroGoal` children for one immutable `WeeklyGoal`.
- **ADR-011 — Navigation:** Today is the default selected tab; all tabs own a `NavigationStack`; Goals is a Statistics destination; internal navigation is typed rather than URL-based.
- **ADR-012 — Sync readiness:** cloud records are user-owned UUID records with timestamps/tombstones where mutable; sync status remains local metadata, and Supabase/auth are deferred.
- **ADR-013 — Calculations:** nutrition, unit conversion, recipe totals, goal lookup, and statistics are domain/application logic, not SwiftUI logic.

## Open Decisions

No Phase iOS 1 blocker is unresolved. The only deferred product decisions are intentionally outside the approved scope:

1. **Future web-to-native transfer UX.** Recommended: Supabase-backed authenticated migration or explicit signed one-time export/import after backup/sync is approved. Do not add hidden automatic transfer.
2. **Future version-conflict UX.** Recommended: retain both immutable versions and show a concise conflict/history indication only when a real multi-device conflict occurs; do not silently discard nutrition data.
3. **Future goal removal behaviour.** Recommended: keep goals append-only until a user need proves a delete/replace flow, then define historical-report semantics before implementing it.
