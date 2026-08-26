# CaloriesTracker Current Code Audit

**Snapshot date:** 2026-08-26  
**Scope:** Current native iOS source, SwiftData persistence, the implemented
optional Supabase synchronization path, and the active documentation set.

## 1. Executive Summary

CaloriesTracker is a native, local-first iOS application with a clear feature →
service → domain → repository boundary and an optional foreground Supabase sync
layer. Product and Recipe histories are append-only immutable versions; Diary
entries hold independent historical snapshots. UUIDs, LocalDay keys, soft
deletes, persistent outbox tokens and account-scoped metadata provide the
implemented synchronization identity and recovery model.

The synchronization audit is complete. Physical-device verification confirmed
bootstrap convergence, idempotent immutable-version round trips, safe push
acknowledgement and incremental pull application. The remaining non-sync code
quality observations are recorded separately below and do not block sync.

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

`AppDependencies` is the composition root. It creates one versioned local-only
SwiftData `ModelContainer`, constructs the repositories and services, and,
when configured, exactly one Supabase client, auth service, transport,
coordinators, status store, change notifier and orchestrator. `AppRouter` owns
the selected tab and three typed `NavigationStack` paths; routes carry IDs and
explicit contexts, not SwiftData model objects.

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
| OBS-01 | ALREADY RESOLVED | — | High-volume navigation, focus and lifecycle telemetry was removed. Feature error mappers retain only unexpected technical failures for diagnostics. |

## 9. Implemented Sync Audit

- SwiftData remains the local source of truth and has CloudKit mirroring
  disabled. Supabase is optional infrastructure; configuration and account
  state cannot block local use.
- One app-owned Supabase client uses OTP auth. A restored cached session is
  emitted but must pass the current-session read before it can schedule sync;
  an expired session is not treated as signed in.
- `SyncOutboxRecord` coalesces local work by typed UUID identity. A changed
  token is acknowledged only after a decoded accepted RPC response and only if
  that exact token is still current. Push persists the account/entity remote
  revision and acknowledgement in one save.
- `push_sync_record` is decoded as exactly one row from its `RETURNS TABLE`
  response, then mapped to typed accepted/conflict/missing outcomes. HTTP
  success without a valid one-row response is not acceptance.
- Account-scoped remote revisions, pull cursors and bootstrap markers are
  monotonic and retained across sign-out. Pull advances only over a safe fully
  handled range; deferred dependency rows, invalid payloads and immutable
  collisions hold the cursor.
- Bootstrap is remote-first, scans local identities only after a caught-up
  pull, seeds only unknown remote states, pushes through the normal coordinator,
  pulls again, and records completion only after convergence.
- Canonical payloads normalize all domain sync `Date` fields to integer Unix
  milliseconds for encoding, equality, fingerprints and LWW ordering. Local
  SwiftData dates are not bulk-rewritten. Immutable ProductVersion and
  RecipeVersion equality is exact after this canonicalization; a genuine same-
  UUID content difference remains an invariant error.
- Mutable Product, Recipe and DiaryEntry merge as whole records under canonical
  millisecond LWW, with sticky tombstones and deterministic canonical-byte
  tie-breaking. WeeklyGoal is a write-once aggregate keyed by `LocalDay`.
- Product name/barcode-only and Recipe name-only saves create/stage only their
  logical record. Versioned changes append and stage the logical record plus the
  new immutable version.
- The actor orchestrator is foreground-only, bounded and single-flight. It
  performs `Pull → Push → Pull`, coalesces wakes, debounces committed local
  changes, refreshes every 60 seconds while active and retries only network or
  server failures with delays 2/5/15/30/60 seconds.
- Sync logs retain one safe summary per push, pull and bootstrap run. Accepted
  items are not logged individually. Remote-apply failures carry safe typed
  context; immutable diagnostics use bounded field-level differences rather
  than full payloads or credentials.

## 10. Physical-device Verification and Audit Result

The following scenarios were verified on a physical iPhone during the sync
hardening sequence:

| Scenario | Observed result |
| --- | --- |
| Initial bootstrap | Remote-first bootstrap converged and stored its account marker only after pull/push/pull completion. |
| Immutable round trip | ProductVersion and RecipeVersion replayed idempotently after canonical timestamp normalization. |
| Push RPC | A 124-record push decoded and acknowledged all 124 accepted rows; the following pull processed all 124 revisions with no failures. |
| Steady state | Repeated unchanged cycles produced Push 0 and Pull 0. |
| Metadata-only edits | Product name-only and Recipe name-only edits each produced exactly one logical-record push, with no new or refreshed version marker. |
| Pull application | Incremental pull applied valid rows, retained safe cursor semantics and did not echo remote imports through ordinary local mutation signalling. |

No server schema, RPC concurrency rule, cursor, bootstrap marker or local-data
reset was required by this audit. No blocking sync work remains.

No automated sync test target is currently present; this audit intentionally
used the prescribed physical-device evidence and no simulator/test run. Adding
automated coverage is future quality work, not a blocker for the implemented
sync behavior.

## 11. Remaining Non-blocking Product Code Quality Work

The existing non-sync findings remain separate from synchronization:

- Catalog search lifecycle cancellation/request identity (LIFE-02).
- Focused VoiceOver labels for date/week navigation (A11Y-01).
- Optional physical split of the large `RecipeViews.swift` file (MAINT-01).

They require separate product decisions and do not change the audited sync
architecture or its completion status.
