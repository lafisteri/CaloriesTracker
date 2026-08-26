# CaloriesTracker Current Code Audit

**Snapshot date:** 2026-08-26  
**Scope:** Current native iOS source, SwiftData persistence, and the active
documentation set. This is a technical baseline for a subsequent Sync Readiness
Review, not a CloudKit design or a new refactoring programme.

## 1. Executive Summary

CaloriesTracker is a native, local-first iOS application with a clear feature →
service → domain → repository boundary. Product and Recipe histories are
append-only immutable versions; Diary entries hold independent historical
snapshots. UUIDs, LocalDay keys, soft deletes and repository protocols give the
application a solid starting point for a future sync discussion.

The correctness, performance and hardening work visible in current code is
substantively complete. The remaining confirmed debt is narrow: Catalog view
lifecycle duplication/search-task cancellation, focused accessibility labels,
the size of `RecipeViews.swift`, and non-standardised observability. None is a
reason to make sync decisions in this document.

## 2. Current Architecture

The implemented dependency direction is:

~~~text
SwiftUI View
→ ViewModel / feature state
→ Application Service
→ Domain values and calculators
→ Repository protocol
→ SwiftData Repository
→ SwiftData records / ModelContainer
~~~

`AppDependencies` is the composition root. It creates one versioned SwiftData
`ModelContainer`, constructs the four repositories, then supplies
`ProductService`, `RecipeService`, `DiaryService`, `GoalService` and
`StatisticsService` to the feature roots. `AppRouter` owns the selected tab and
three typed `NavigationStack` paths; routes carry IDs and explicit contexts,
not SwiftData model objects.

Views own presentation and transient navigation. View models own feature state
and invoke services. Services resolve versions, validate, calculate and write
through Domain repository protocols. SwiftData records remain inside Data.

## 3. Data Model and Persistence Invariants

| Entity | Identity and mutability | Time / delete semantics | Important references and repository ownership |
| --- | --- | --- | --- |
| Product | Client-generated UUID; name, barcode and current-version pointer are mutable logical metadata. | `createdAt`, `updatedAt`, `deletedAt`; user delete is soft. | `ProductRepository`; `currentVersionID` selects the version used by new actions. |
| ProductVersion | UUID, `productID`, optional `basedOnVersionID`, display version number; immutable base unit, base amount and nutrition. | `createdAt`; never edited or soft-deleted. | `ProductRepository`; append-only history. |
| Recipe | UUID; mutable name and current-version pointer. | `createdAt`, `updatedAt`, `deletedAt`; user delete is soft. | `RecipeRepository`; current pointer selects new composition/Diary sources. |
| RecipeVersion | UUID, `recipeID`, optional lineage and version number; immutable ingredient composition, output and total nutrition. | `createdAt`; never edited or soft-deleted. | `RecipeRepository`; append-only history. |
| RecipeIngredient | UUID owned by one RecipeVersion; immutable position, logical Product ID, exact ProductVersion ID, amount/unit and normalized amount. | No independent audit/deletion fields; replaced only by a new RecipeVersion. | Persisted RecipeVersion child; no persisted Recipe → Recipe edge. |
| DiaryEntry | UUID; mutable only through constrained amount/unit update, explicit source rebase, or move/reorder. | `createdAt`, `updatedAt`, `deletedAt`; user delete is soft. | `DiaryRepository`; stores source and nutrition snapshots rather than a live relationship. |
| WeeklyGoal / DailyMacroGoal | UUID weekly goal with a unique effective LocalDay and seven owned daily values. Goals are created for effective dates rather than edited in place. | Weekly goal has `createdAt`; current schema has no goal soft delete or `updatedAt`. | `GoalRepository`; effective-date lookup selects the historical goal. |

All persistent identities are UUIDs. `LocalDay` is a validated `YYYY-MM-DD`
civil-date key, not a persisted timestamp. SwiftData relationships help local
ownership traversal, while ID fields are the source of truth for historical and
polymorphic references. Normal user deletion is a logical delete and does not
cascade through retained version history.

Version invariants are central:

- Product and Recipe version data is append-only.
- Each RecipeIngredient pins the exact ProductVersion used for calculation.
- Selecting a Recipe as an ingredient flattens its current composition into
  Product ingredient drafts; nested Recipe composition is never persisted.
- A DiaryEntry stores source type, logical ID, source-version ID, source name,
  amount/unit and nutrition at the time of the entry.

## 4. Feature Architecture

### Today and Amount

Today is organised around a selected `LocalDay` and four meal sections. Its
load is request-scoped: an older async completion cannot replace the data or
goal for a newer selected day. Tap opens the Amount/Edit flow, explicit trash
soft-deletes, and drag/drop delegates reorder or cross-meal move to
`DiaryService`.

Amount uses the same calculation source for preview and the persisted Diary
snapshot. A normal existing-entry amount edit resolves its saved source version.
An ordinary Product edit does not alter history. The narrow contextual exception
is Product editing launched for one existing DiaryEntry: that entry alone is
rebased after save, with preserved amount, reconciled unit, refreshed source
name, recalculated nutrition and a source-version ID changed only when the
ProductVersion changed. A new-entry Amount Product edit refreshes its source
before creation; it does not create an entry from a stale Product state.

### Catalog and quick-add

Catalog is a reusable presentation layer with management and typed selection
contexts. Full-row selection opens Amount; `+` is quick-add. Defaults use the
latest compatible usage, falling back to `100 g` or `1 serving`. Catalog
preview, Amount initial value and quick-add semantics are one invariant.

Quick-add ownership is deliberately feature-local:

~~~text
TodayView → TodayViewModel → DiaryService
RecipeEditorView → RecipeEditorViewModel → RecipeService
~~~

`CatalogQuickAddState` allows one Product or Recipe quick-add operation at a
time inside one selection flow. It is not an application-wide lock.

### Recipe Editor

Recipe creation and update calculate the entire proposed composition before a
version is constructed or persisted. A Product row goes through ingredient
Amount and yields one draft; a Recipe row goes through composition Amount and
yields flattened Product drafts. Confirmed drafts are appended to the current
editor state and nutrition is recalculated.

Ingredient Catalog presentation intentionally waits for actual UIKit keyboard
dismissal when the Recipe Editor has an active text focus. Amount focus
restoration is similarly route-scoped after a child Product editor returns.

## 5. Data Access / Performance Status

The current data-access principle is to batch known-ID relationships, use a
targeted predicate for a simple known-field lookup, and use a bounded,
specialised query for latest usage defaults. Services restore semantic ordering
in memory when storage order is not the product order.

| Historical finding | Current code evidence | Status |
| --- | --- | --- |
| PERF-01 | `DiaryRepository.latestActiveUsages(for:)` accepts only requested sources and SwiftData selects the latest active usage per source with a bounded read. | ALREADY RESOLVED |
| PERF-02 | `ProductService.products(matching:)` and `RecipeService.recipes(matching:)` collect current-version IDs, batch-fetch versions, then build lookup dictionaries. | ALREADY RESOLVED |
| PERF-03 | Recipe detail/source resolution batch-fetches pinned ProductVersions and Products; editor appends resolved ingredient sources as a batch. | ALREADY RESOLVED |
| PERF-04 | Barcode, version-history and simple goal lookups use SwiftData predicates; single-result reads use a limit and goals use storage sort order. | ALREADY RESOLVED |

## 6. Correctness and Lifecycle Status

| Historical finding | Current code evidence | Status |
| --- | --- | --- |
| COR-01 | Amount refreshes a current Product for a new entry; contextual existing-entry Product editing invokes the explicit one-entry rebase path. | ALREADY RESOLVED |
| DATA-01 | `EditableDecimal` accepts `.`/`,` and at most two fractional digits while calculation values retain `Double` precision. | ALREADY RESOLVED |
| LIFE-01 | Today identifies each selected-day request and ignores stale success/failure completions. | ALREADY RESOLVED |
| UX-01 | Product/Recipe destructive delete is exposed through explicit trash actions rather than full-swipe execution. | ALREADY RESOLVED |
| CON-01 | Shared `CatalogQuickAddState` protects both Product and Recipe quick-add within one Recipe selection flow. | ALREADY RESOLVED |
| ARC-01 | Today and Recipe Editor view models own quick-add application orchestration; Catalog receives typed callbacks. | ALREADY RESOLVED |
| Recipe ingredient Amount regression | Recipe Editor sequences pending ingredient Catalog presentation after keyboard dismissal; Amount focus restoration is route-aware. | ALREADY RESOLVED |

## 7. Error and Numeric Integrity

Manual input validation remains distinct from calculation precision. Product,
Recipe, Diary and Goal editable decimals are finite user values with at most two
fractional digits; derived values retain full precision.

`Nutrition.scaled` and `Nutrition.adding` reject non-finite operands, factors
and results. Recipe ingredient totals/output scaling, recipe-to-ingredient
flattening and Diary nutrition scaling propagate this failure before a derived
value can be persisted. Diary and Statistics aggregation also fail rather than
fabricating a non-finite total. There is no clamp of NaN or infinity to a
different value. Recipe create/update calculates before the repository write,
so a failed aggregate cannot create a partial RecipeVersion.

Feature mappers keep useful validation/business messages and replace unknown
SwiftData, mapping or system errors with stable operation-specific text. The
underlying error is emitted to `Logger`, not presented through
`localizedDescription` in UI.

| Historical finding | Current code evidence | Status |
| --- | --- | --- |
| VAL-01 | Throwing Nutrition calculation boundary rejects non-finite results before Recipe/Diary persistence. | ALREADY RESOLVED |
| ERR-01 | Product, Recipe, Diary, Goal, Statistics and Catalog quick-add feature paths map UI errors and log technical causes. | ALREADY RESOLVED |

## 8. Known Technical Debt

Only the findings below remain evidenced in the current repository. They are
not implemented by this audit.

| ID | Status | Priority | Evidence |
| --- | --- | --- | --- |
| LIFE-02 | CONFIRMED | Medium | Product and Recipe Catalog list views each start initial loads from both `.task` and `.onAppear`; search changes start independent tasks without cancellation, debounce or request identity, so an older search can publish after a newer query. LIFE-01 protects Today only. |
| A11Y-01 | CONFIRMED | Low | Several important controls have labels, but Today day-navigation and Statistics week-navigation chevron controls lack explicit accessible labels/hints. No complete VoiceOver audit is encoded in the source. |
| MAINT-01 | CONFIRMED | Low | `RecipeViews.swift` is about 1,040 lines and contains list, detail, editor, ingredient Amount and composition Amount view types. Its physical split is deferred. |
| DEAD-01 | NO LONGER APPLICABLE | — | Current source review did not establish a concrete unused production member that justifies a cleanup-only change. No dead-code deletion is proposed. |
| OBS-01 | CONFIRMED | Low | Useful navigation, focus and error logs exist, but there is no documented, consistent observability convention or correlation strategy across feature flows. |

## 9. Sync-Relevant Strengths

- Stable client-generated UUIDs exist for every persistent root and owned child.
- ProductVersion and RecipeVersion are immutable, append-only facts with
  explicit lineage and creation time.
- Recipe composition records exact ProductVersion pins rather than resolving
  mutable current values later.
- DiaryEntry is a self-contained historical snapshot with source IDs, version
  ID, source name, amount/unit and nutrition.
- Product, Recipe and DiaryEntry retain `deletedAt` tombstones through soft
  delete; logical roots have `createdAt` and `updatedAt` where they are mutable.
- Repository protocols isolate the local SwiftData implementation, and the
  schema/migration plan is explicit and versioned.
- Numeric/error hardening prevents newly derived invalid doubles and raw
  infrastructure messages from crossing normal feature boundaries.

## 10. Sync-Relevant Risks / Open Questions

These are observations for the next review, not decisions:

- The current schema has no sync metadata, change token, remote revision or
  conflict policy. Product/Recipe/Diary timestamps alone do not define merge
  behaviour.
- Soft-delete tombstones exist for Product, Recipe and DiaryEntry, while
  immutable versions and WeeklyGoal do not have equivalent delete metadata.
  A future delete-vs-edit policy is therefore a product/architecture decision.
- WeeklyGoal is keyed by one effective LocalDay and has `createdAt` but no
  `updatedAt` or soft delete. Its multi-device semantics need an explicit
  decision.
- SwiftData relationships model local ownership, but IDs are authoritative for
  historical references. Any remote representation must preserve this
  distinction without relying on local object graph identity.
- Current repositories and UI-facing services are MainActor/local-container
  oriented. A sync/import transaction model must define isolation and UI update
  boundaries.
- No automated test target or test suite is present in this repository snapshot.
  Sync design should establish verification for merge, tombstone and historical
  snapshot scenarios before implementation.

## 11. Recommended Next Phase

Conduct a separate **Sync Readiness Review**. It should map the existing entity
identities, immutable-version rules, historical snapshots and soft-delete
semantics to sync requirements, then explicitly decide conflict handling,
metadata, deletion policy, transaction boundaries and verification strategy.
It should not assume a CloudKit record shape or merge algorithm from this audit.
