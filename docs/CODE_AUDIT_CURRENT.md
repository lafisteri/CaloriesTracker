# CaloriesTracker Current Code Audit

**Snapshot date:** 2026-08-27  
**Scope:** P1 WeeklyGoal identity and legacy synchronization safety.

## P1: Canonical WeeklyGoal identity — FIXED

`WeeklyGoal.effectiveFrom` is the aggregate's logical identity. Its persisted
and sync UUID is UUIDv5 using fixed namespace
`6E770171-4E9D-4E0C-8BC7-0C64A5CB6D52` and the UTF-8 canonical LocalDay value
`YYYY-MM-DD`. New goals and same-day edits therefore use the same UUID on every
device; a different effective day uses a different UUID.

At app startup and before each pull, push or bootstrap boundary,
`SyncLocalStore` idempotently normalizes legacy random local goal UUIDs. It
preserves `effectiveFrom`, `createdAt`, `updatedAt` and all seven daily values,
updates only the owned daily-goal foreign IDs, removes stale legacy outbox keys
through their exact tokens, and coalesces pending work into one canonical key.
This is data normalization, not a SwiftData V6 migration.

Pull separates an old physical Supabase alias key from the canonical local key:
the alias's server revision remains stored under the actual remote key, while
its payload merges into the canonical local aggregate. The winning aggregate is
republished only under the canonical key, and any obsolete alias outbox marker
is removed in the same pull transaction. Legacy cloud alias rows may remain
inert; they cannot create a second local WeeklyGoal, become an active local
identity, block the cursor, or cause a `missingEntity` retry loop.

WeeklyGoal content remains a complete seven-day aggregate under canonical
millisecond `updatedAt` LWW, followed by the existing canonical-payload
tie-break. The winner's UUID never chooses logical identity. Same-day edits,
historical effective-date lookup and the old-payload `updatedAt = createdAt`
fallback remain unchanged.

No Product, Recipe, Diary, SQL/RLS/RPC, authentication, cursor, conflict-rule
or UI behavior changed. No automated test target or simulator run was added.
