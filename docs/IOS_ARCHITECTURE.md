# Native iOS architecture and data design

**Status:** Current native iOS architecture
**Last updated:** 2026-08-26
**Scope:** the Swift / SwiftUI application. PRODUCT_SPEC.md defines user-visible
behaviour; this document defines technical boundaries and invariants.

## Target platform

| Concern | Current decision |
| --- | --- |
| UI | SwiftUI on iOS 17.0+. UIKit is used only for platform APIs. |
| Navigation | TabView and one typed NavigationStack path per root tab. |
| Local persistence | One SwiftData ModelContainer from a versioned schema. |
| Concurrency | async/await; UI and SwiftData repositories are MainActor. |
| Observation | Swift Observation is normal feature state. Combine is scoped to Recipe Editor keyboard lifecycle notifications. |
| Data | Local-first SwiftData source of truth. Supabase auth and transport are optional infrastructure, not an automatic sync service. |

The active implementation is the native iOS client. Web/PWA architecture is not
a native implementation dependency.

## Architecture

~~~text
SwiftUI View
    ↓ user intent and rendered state
ViewModel / feature state
    ↓ commands and read models
Application Service
    ↓ domain values and calculators
Domain
    ↓ repository protocol
Repository protocol
    ↓
SwiftData Repository
    ↓
SwiftData records / ModelContainer
~~~

### Layer responsibilities

- **Views** render state and forward intent. They do not use Query,
  ModelContext or persistence records directly, calculate nutrition, or decide
  versioning.
- **View models and feature state** own transient form, loading/error and
  feature navigation state. They invoke services, not repositories.
- **Application services** coordinate validation, version resolution,
  calculation, snapshot creation, ordering and persistence.
- **Domain** contains value types, LocalDay, persistent enums, calculators and
  repository protocols. It has no SwiftUI or SwiftData imports.
- **Data** contains records, mappers, repositories and migrations. Model
  objects do not cross the repository boundary.

AppDependencies is the composition root: it creates one ModelContainer,
repositories and services, then injects services into feature roots. The app
intentionally remains one target rather than separate Swift packages.

## Persistence and Supabase sync foundation

SwiftData is the local source of truth. The production `ModelContainer` is
explicitly local-only, with automatic cloud mirroring disabled.

Supabase is the current network transport foundation and remains outside
SwiftData. `AppDependencies` optionally owns one `SupabaseClient` through
`SupabaseClientProvider`; no client is made by a view, repository or request.
The client uses the project URL and a publishable key from `Supabase.xcconfig`
(with an ignored private override for local or CI configuration). No service
role, database, PAT, SMTP or other secret credential belongs in the iOS app.

Supabase authentication is passwordless email OTP (`requestOTP`, `verifyOTP`,
restored `currentSession`, and `signOut`). It is optional: there is no login
wall, and missing configuration, a missing session or network access never
prevents normal local use of CaloriesTracker.

`SupabaseSyncTransport` performs only typed network requests. Server writes go
through the RLS-protected `push_sync_record` RPC, which derives ownership from
the authenticated user rather than an iOS-supplied owner identifier. Reads use
RLS on `sync_records`. `server_revision` is transport cursor metadata, ordered
strictly ascending for incremental pulls; it is not part of canonical payloads.
The transport returns accepted, conflict or missing results, including the
authoritative conflict payload, but does not apply a local merge.

`SyncPushCoordinator` is the only current connection from the persistent
outbox to the transport, and it is an explicit manual API: it is not run on
launch, foreground, edit, login or a timer. It reads at most 50 immutable outbox
snapshots in `enqueuedAt ASC, key ASC` order, exports each canonical envelope,
uses that entity's account-scoped remote revision for optimistic concurrency,
and pushes items sequentially. For an accepted response it persists the new
entity revision and acknowledges only the snapshot's exact outbox token in one
`ModelContext.save()`. If an edit changes that token while the request awaits,
the new outbox item remains pending while the accepted remote revision is kept.
Conflicts and missing remote records remain pending without merge, retry,
metadata rewrite or recovery. Pushes never change the pull cursor.

The app remains fully usable offline: synchronization must not block adding or
editing local data.

Product, Recipe and DiaryEntry are mutable sync entities with stable UUID
identity and `createdAt` / `updatedAt` / `deletedAt` business timestamps. Their
user-visible deletion is a retained tombstone. ProductVersion and RecipeVersion
(including its RecipeIngredient children) are immutable: remote data may insert
an unknown version, but a known version must be canonical-payload equivalent or
is treated as a corruption/invariant error.

WeeklyGoal and its seven DailyMacroGoal values are a write-once aggregate for
one `effectiveFrom` key. It has a stable UUID and `createdAt` records its sole
local mutation; goals are not edited or deleted in place.

Business timestamps are distinct from sync operational metadata. That metadata
is infrastructure-only and never appears in domain values or canonical payloads.

For a local user mutation, the affected domain record and its persistent,
local-only outbox marker are committed by the same `ModelContext.save()`. Outbox
items coalesce by stable typed identity (`entityType:entityID`): a later local
mutation replaces the change token and enqueue time instead of adding a second
pending item. A future acknowledgement may remove an item only when its token
still matches the uploaded token.

Product, Recipe and DiaryEntry tombstones are synchronized as the current
entity state. RecipeVersion includes its ingredient composition and WeeklyGoal
includes its daily values as their respective sync aggregates. The V2 migration
adds an empty outbox table only; existing local records are not backfilled.

The V3 migration adds empty, account-scoped Supabase metadata only. Server
revisions are monotonic per Supabase account: `SyncRemoteStateRecord` maps
`accountID + SyncEntityKey` to a known positive `serverRevision`, while
`SyncPullStateRecord` maps an account to its fully processed incremental-pull
cursor (default `0`). The deterministic remote-state
key is `<account UUID>:<entity type>:<entity UUID>`. `SyncMetadataStore` uses
targeted predicate queries and permits callers to combine metadata mutation
with other changes in one `ModelContext.save()`; it never saves internally.
Revisions and cursors are monotonic and reject regression rather than silently
using a maximum. A pushed entity revision never advances the pull cursor: other
account changes may still exist before that revision.

Signing out retains local data, outbox rows and account-scoped metadata. A later
sign-in to the same account can reuse its metadata, while another account gets
an isolated namespace. No migration backfills revisions or treats current local
records as uploaded.

Outbox marking is explicit at local mutation save boundaries, rather than an
automatic SwiftData side effect. A future remote-import path can therefore write
remote state without creating another pending local change.

### Canonical payload and remote merge foundation

The sync boundary is independent of SwiftData and any network transport. Every transfer
uses a `SyncPayloadEnvelope` with `schemaVersion: 1`, an explicit entity type
(`product`, `productVersion`, `recipe`, `recipeVersion`, `diaryEntry`, or
`weeklyGoal`) and a UUID. The same `SyncEntityKey` is used by the outbox and
payload export, so there is no runtime-type-name or second identity mapping.
Only these six top-level payloads exist: RecipeVersion embeds its ordered,
pinned ingredients and WeeklyGoal embeds its seven ordered daily values.

`SyncLocalStore.payload(for:)` exports the current local state immutably,
including tombstones. A missing physical record for a requested key is an
invariant error, never an empty or synthetic payload. `applyRemote` validates a
payload, checks dependencies, resolves conflicts and saves directly through a
SwiftData `ModelContext`; it never marks an outbox record and therefore cannot
echo a pull back into a future push. Its result distinguishes insertion, remote
application, identical content, local-wins, dependency deferral and explicit
republish effects.

Product, Recipe and DiaryEntry use whole-record last-writer-wins by `updatedAt`.
Tombstones are sticky: a tombstone always wins over a non-tombstone; two
tombstones use the same timestamp rule. WeeklyGoal competes as a whole aggregate
by its natural `effectiveFrom` key and `createdAt`. For an equal timestamp, the
canonical sorted-key JSON bytes of the version-1 envelope break the tie; the
lexicographically greater payload wins. This is deterministic and
direction-independent.

Remote Product/Recipe current-version references, RecipeVersion pinned
ProductVersions and DiaryEntry source versions are dependencies. Missing
dependencies return a typed deferred result with the exact missing keys; no
fallback snapshot or placeholder is invented. RecipeVersion validates child IDs
and ordering, finite values, units and pins, then verifies its supplied totals
and normalized amounts with `RecipeCalculator` without rewriting payload values.

Barcode uniqueness includes deleted Products. A collision keeps the newer
Product by the same timestamp/canonical rule, clears only the losing barcode and
returns that Product as a `needsRepublish` effect. Local-wins outcomes also
return explicit republish effects; neither path writes an outbox row. There is
no persistent schema change, staging queue or networking dependency in
this foundation.

## Project structure

~~~text
ios/
  App/                         # app entry point, dependencies, router and tabs
  Domain/
    Core/ Products/ Recipes/ Diary/ Goals/ Statistics/ Units/ Repositories/
  Application/
    Products/ProductService.swift
    Recipes/RecipeService.swift
    Diary/DiaryService.swift
    Goals/GoalService.swift
    Statistics/StatisticsService.swift
  Data/SwiftData/
    Models/ Mappers/ Repositories/ SchemaV1.swift MigrationPlan.swift
    SyncEntityIdentity.swift SyncMetadata.swift CanonicalSyncPayloads.swift
    SyncLocalStore.swift
  Data/Supabase/
    SupabaseClientProvider.swift SupabaseAuthService.swift SupabaseSyncTransport.swift
    SyncPushCoordinator.swift
  Features/
    Today/ Catalog/ Statistics/ Goals/
~~~

## Navigation

### Root tabs and paths

AppRouter owns the selected tab and three typed paths:

~~~text
Статистика → statisticsPath
Сегодня    → todayPath
Продукты   → catalogPath
~~~

Goals is a Statistics destination. Catalog owns Product/Recipe details, editors
and histories. Today owns selection, Amount and contextual editor routes.
Routes carry IDs and explicit context, never URLs or captured SwiftData objects.
DiaryContext carries LocalDay and MealType; FoodSourceReference carries
SourceType and logical source ID.

Paths are independent with one intentional exception: leaving the Today tab
clears todayPath. This discards unfinished transient flows so returning shows
Today root. The selected LocalDay lives in TodayViewModel, independent of the
path, and is not reset.

Completion callbacks use guarded router pop helpers: an async completion may pop
only if its expected route is still at the top. This prevents stale callbacks
from removing an unrelated screen.

### Today request lifecycle

Today loading is request-scoped. A day navigation action captures the selected
`LocalDay`; only the most recent request may publish its success, failure or
loading completion. An older request therefore cannot show the entries or goal
of a different day after the user has moved on. This is a feature-state
correctness rule, independent of any future cancellation optimisation.

### Shared selection flow

~~~text
Today meal → Catalog(selection) → Amount → DiaryService.create/quickAdd → Today root
Recipe Editor → Catalog(selection) → ingredient Amount → draft(s) → Recipe Editor
~~~

A successful Today add clears completed selection/Amount routes. Recipe selection
mutates only the Recipe Editor draft. Typed callbacks express that difference;
they do not require separate Catalog screens.

### Quick-add coordination

CatalogQuickAddState is scoped to one selection flow. Only one Product or
Recipe quick-add command may be active in that flow. It is not a global app
lock.

Quick-add orchestration belongs to the receiving feature, not Catalog:

~~~text
TodayView → TodayViewModel → DiaryService
RecipeEditorView → RecipeEditorViewModel → RecipeService
~~~

Catalog remains a reusable presentation layer. Its typed selection context and
callbacks carry the intent; it does not resolve sources or write persistence.

## Shared UI boundaries

### Catalog

CatalogView has two explicit modes:

~~~text
management
selection(FoodSelectionContext)
~~~

It shares Product/Recipe segments, search, row layout and creation action. The
typed context determines semantics:

| Mode | Full row | Quick-add |
| --- | --- | --- |
| Management | Open details | Not available |
| Today selection | Open Diary Amount | Persist DiaryEntry |
| Recipe ingredient selection | Open ingredient Amount | Add Product draft(s) |

Shared visual code must not acquire persistence knowledge. New flows with the
same interaction contract add an explicit context/callback rather than
duplicating Catalog.

### Amount

AmountEditorView is shared by Diary create/edit, Product ingredient amounts,
flattened Recipe amounts and existing ingredient editing. It owns amount input,
unit presentation, nutrition preview and keyboard-safe bottom action UI. The
caller owns source resolution, validation, confirmation and navigation.

A Product has one base-unit option. A Recipe exposes grams for cookedWeight,
serving for servingsCount, or both. Unit switching only changes the selected
unit; it does not convert the entered number.

Amount accepts an optional focus binding so a caller can suppress focus while a
child Product editor is pushed. The router's amount-focus restoration revision
then allows only the still-current Amount route to restore numeric focus on
return. This is an intentional lifecycle compatibility mechanism, not a way to
focus a stale route.

Manual editable decimal values accept at most two fractional digits; `.` and `,`
are both valid separators. Their serializer and parser are deliberately separate
from read-only display formatting. This constraint applies only to user-entered
text: nutrition, recipe, diary, statistics and goal calculations retain their
calculation precision.

### Recipe Editor keyboard transition

Recipe Editor coordinates presentation of Ingredient Catalog locally:

~~~text
tap Add ingredient
→ record pending presentation
→ clear Recipe Editor FocusState
→ if UIKit keyboard is visible, wait for keyboardDidHide
→ present Catalog
~~~

FocusState becoming nil does not guarantee UIKit's hide animation has finished.
The Editor therefore observes keyboardDidShowNotification and
keyboardDidHideNotification only while it exists and only as lifecycle signals.

These notifications must not grow into keyboard frame/height handling, manual
padding, safe-area compensation or global keyboard state. Recipe Editor
intentionally has no custom keyboard toolbar because a hidden parent toolbar
interfered with nested Amount keyboard lifecycle.

## Domain model and historical integrity

### Identity and LocalDay

All persistent domain identities are client-generated UUIDs. LocalDay is a
validated Gregorian civil date encoded as zero-padded YYYY-MM-DD, not a
timestamp.

- DiaryEntry.day and WeeklyGoal.effectiveFrom persist this key.
- Formatting and date-picker conversion use a local-noon Date that is never
  persisted as the diary day.
- createdAt, updatedAt and deletedAt are absolute Date instants.

This preserves the day across UTC conversion, daylight-saving changes and
travel.

### Versioned sources

~~~text
Product (logical identity)
├── logical metadata: name, barcode
└── current ProductVersion
    └── immutable: base unit, base amount, calories, protein, fat, carbs

Recipe (logical identity)
├── logical metadata: name
└── current RecipeVersion
    ├── immutable: ingredients and their persisted order
    ├── immutable: cookedWeight, servingsCount and derived total nutrition
    └── RecipeIngredient (immutable child) → pinned ProductVersion
~~~

Product.currentVersionID and Recipe.currentVersionID select sources for new
actions. Versions are append-only immutable values with basedOnVersionID
lineage and display version number.

A metadata-only save updates the logical Product or Recipe while retaining its
currentVersionID. For Product this is name and barcode; for Recipe it is name.
`saveLogicalMetadata` is therefore an intentional architecture path, not a way
to mutate an existing version. A version append is required only when its owned
versioned data changes: Product base unit/base amount/nutrition, or Recipe
composition (including ingredient order, pin, amount and unit) or output.

A RecipeIngredient stores both logical Product ID and exact ProductVersionID.
Recipe nutrition must resolve that pin, never Product.currentVersionID.
Selecting a Recipe as an ingredient is flattened into Product ingredient
drafts; persisted data has no nested Recipe→Recipe dependency.

### Diary snapshots and soft delete

DiaryEntry stores source type, source ID, source version ID, source name,
amount, unit, nutrition, day, meal and order. New entries resolve the selected
source's current version once. Existing-entry amount edits resolve saved
sourceVersionID, not a current source version. Historical snapshots are stable
by default: ordinary Product/Recipe edits never rewrite them.

An explicit Product edit initiated from one DiaryEntry is the narrow exception:
DiaryService may rebase that one Product-sourced entry to Product.currentVersionID,
refresh its source-name and nutrition snapshots, and preserve its identity and
placement. This application-service operation never bulk-updates history. Move/
reorder may change only meal, order and audit time.

User-visible Product, Recipe and DiaryEntry deletion is soft. It removes active
sources from Catalog but must not destroy versions/ingredients needed for
historical Recipe and DiaryEntry resolution.

## SwiftData persistence

CaloriesTrackerSchemaV3 is the active explicit VersionedSchema. AppDependencies
creates the container with CaloriesTrackerMigrationPlan, which uses lightweight
V1→V2 and V2→V3 migrations. V3 is additive: it does not rewrite existing user
records or SyncOutbox rows, and starts with no remote or pull metadata.

| Record group | Purpose |
| --- | --- |
| ProductRecord, ProductVersionRecord | Product identity and immutable version data |
| RecipeRecord, RecipeVersionRecord, RecipeIngredientRecord | Recipe identity, version and pinned ingredients |
| DiaryEntryRecord | Historical source and nutrition snapshot |
| WeeklyGoalRecord, DailyMacroGoalRecord | Effective goal and seven daily values |
| SyncOutboxRecord | Coalesced local mutation marker (added by V2) |
| SyncRemoteStateRecord | Account + entity known positive server revision (added by V3) |
| SyncPullStateRecord | Account's fully processed incremental-pull cursor (added by V3) |

Every record has a unique UUID; enum values are scalar string raw values.
Record relationships support local traversal, but UUID fields are authoritative
for polymorphic/historical references. Recipe-version ingredients and weekly
goal daily values are owned children. Normal user deletion never cascades
through history.

## Repository boundary and query strategy

Repository protocols pass domain values, not Model objects or ModelContext. They
provide individual and bounded collection lookups. A caller that knows a set of
IDs must deduplicate and fetch the set rather than issuing a per-row call.

Performance rules:

- Use a bounded predicate instead of a full-table scan when possible.
- Batch current versions for logical Product/Recipe source sets.
- Batch ProductVersions and Products needed to resolve Recipe ingredients.
- Query latest Diary usage defaults only for requested source sets.
- Restore semantic ordering after a batch fetch; storage return order is not
  UI order.

Catalog services fetch logical sources and batch their current versions. Recipe
detail resolution batches pinned ProductVersions and Products, yielding one
resolved ingredient graph for read models, nutrition and outdated status.

## Application services and calculations

| Service | Responsibility |
| --- | --- |
| ProductService | Listing/details, validation, version append, metadata and soft delete |
| RecipeService | Source resolution/pinning, composition calculation, versioning, flattening and output preview |
| DiaryService | Day totals, usage defaults, Amount source/preview, snapshot create/edit, delete and move/reorder |
| GoalService | Seven-day validation, creation and effective-date lookup |
| StatisticsService | Aggregation from Diary snapshots and historical goals |

Amount preview and persisted DiaryEntry use the same calculation path. Recipe
calculation is intentionally split:

~~~text
ingredient composition → pinned versions + total nutrition
output projection      → cookedWeight / servingsCount preview
~~~

Changing only output fields recomputes projection from the existing composition;
it must not resolve the ingredient graph from repositories again. Formulae
belong in the domain/application calculation layer, never in SwiftUI views.

### Numeric and error integrity

Manual editable decimal text accepts at most two fractional digits and accepts
both `.` and `,`. This input constraint does not round or reduce internal
calculation precision. Nutrition scaling and aggregation reject non-finite
operands, factors and results; a derived numeric value used for Product/Recipe,
RecipeIngredient or Diary snapshot persistence must be finite. NaN and ±Infinity
are rejected rather than clamped or silently substituted.

Feature error state preserves useful domain validation messages. Unknown
infrastructure, mapping or system errors are logged with technical detail and
presented to the user only through a stable context-specific message.

## Current and deferred capabilities

SwiftData remains the only persistence implementation and the local source of
truth. Supabase provides an internal, optional email-OTP and typed transport
foundation, including persistent account-scoped revision and pull-cursor metadata
and an explicit manual outbox push API. There is no sync UI, automatic worker,
initial upload, pull, remote merge application,
staging queue, web migration, barcode scanner wrapper or external product API.
Canonical payload export and direct local remote-merge support remain internal
foundation rather than a user-facing import/export feature.

If future sync is approved, it must remain behind repositories, use explicit
DTOs/merge transactions and preserve immutable versions and Diary snapshots.
Camera barcode scanning likewise requires a separately approved isolated
feature; it must not be presented as current architecture.

## Architecture decisions

- **ADR-001 — Native foundation:** iOS 17+, SwiftUI, SwiftData, NavigationStack
  and TabView.
- **ADR-002 — Local persistence:** SwiftData is local-only behind repository
  protocols.
- **ADR-003 — Identity and dates:** UUID identities and civil LocalDay keys.
- **ADR-004 — Version pinning:** immutable Product/Recipe versions; Recipe
  ingredients pin ProductVersion IDs.
- **ADR-005 — Diary history:** source-version and nutrition snapshots; historic
  edits use that source version.
- **ADR-006 — Deletes:** logical deletes are soft and preserve history.
- **ADR-007 — Shared UI:** Catalog and Amount are reused through typed context.
- **ADR-008 — Today navigation:** leaving Today clears only transient todayPath.
- **ADR-009 — Safe navigation:** guarded pop helpers reject stale routes.
- **ADR-010 — Query bounds:** known-ID resolution is batched/deduplicated; no
  catalog-current-version or recipe-detail N+1.
- **ADR-011 — Recipe preview:** output projection is separate from composition
  resolution.
- **ADR-012 — Keyboard lifecycle:** local Editor notifications sequence Editor
  to Ingredient Catalog and are not layout measurements.
- **ADR-013 — Amount focus:** restore focus only to the current Amount route
  after its child editor dismisses.
- **ADR-014 — Request-safe Today:** only the latest selected-day request may
  update Today state.
- **ADR-015 — Numeric integrity:** persisted calculated nutrition is finite;
  manual-input precision and calculation precision are separate concerns.
- **ADR-016 — Error boundary:** user-facing feature errors are mapped; raw
  persistence and system messages stay in diagnostics.
