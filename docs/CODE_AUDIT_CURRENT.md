# CaloriesTracker Current Code Audit

**Snapshot date:** 2026-08-28

## Open findings

- P0: 0
- P1: 0
- P2: 0 confirmed open findings

## Latest P2: Catalog last-used semantics — FIXED

`latestActiveUsages` selects the active DiaryEntry that was created most
recently: `createdAt`, then a deterministic UUID tie-break. It does not use
`updatedAt`. Product and Recipe Catalog defaults therefore retain the amount and
unit from the last added compatible entry; reorder, meal move and contextual
source rebase cannot make an older entry appear newly used. Soft-deleted entries
remain excluded, and the repository continues to return amount, unit and source
identity unchanged.

## Current integrity baseline

- ProductVersion and RecipeVersion validate strict same-owner sequential
  lineage; missing remote bases defer, contradictory existing bases are corrupt.
- WeeklyGoal uses deterministic effective-date identity, preserves historical
  lookup and normalizes legacy local/remote aliases at the sync boundary.
- Remote merge validates domain invariants in the Pull-owned transaction;
  account-pinned sync, exact-token Outbox acknowledgement and cursor semantics
  remain intact.
- Healthy bounded sync work continues as `moreWork`; only real blockers become
  blocked, and transient Push failures stop the remaining batch for scheduled
  retry.
- Today, Statistics, RecipeDetail and Catalog loads protect their published
  state from stale requests; production save/create flows reject a second
  in-flight invocation.

## Deliberately deferred

- Move from MainActor repositories to ModelActor only if measured performance
  requires it.
- Adopt Swift 6 strict concurrency in a dedicated compatibility pass.
- Freeze historical SwiftData schemas before the next structural migration.
- Add live UI refresh for multi-device Pull only if that product scenario is
  introduced.
- Define server-reset/cloud-recovery UX only if recovery is required.
