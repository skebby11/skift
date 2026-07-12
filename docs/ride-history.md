# Ride history

*Design note, 2026-07-12. Promoted from the backlog into v1.x scope. See
Plan.md §9 (decision log).*

## Goal

Completed rides currently vanish when the summary sheet closes — the TCX
export is the only artifact, and only if the rider remembers to save it.
Persist every completed ride locally and let the rider browse past rides and
re-export them later.

## Scope

In: automatic save on ride completion, a History screen (list: date,
distance, duration, average power), re-export to TCX from history, deleting
a ride. Out: cloud sync, charts/graphs per ride, comparisons/ghost rider,
editing, importing external files, pagination (a season of daily rides is
a few hundred small files — fine to list eagerly).

## Architecture

- **`StoredRide`** (new, `SkiftKit`) — `Codable` value: `id: UUID`,
  `startDate: Date`, the summary numbers shown in the list, and the full
  `[RideRecorder.Sample]` so TCX re-export produces exactly what the
  post-ride export would have (samples are ~1/s; a 2 h ride is a few
  hundred KB of JSON — acceptable, revisit if rides ever stream).
- **`RideStore`** (new, `SkiftKit`) — filesystem-backed store, directory
  injected at init so tests use a temp dir. Default directory:
  `~/Library/Application Support/Skift/rides/` (created on demand; the app
  is sandboxed so this lands in the container). One JSON file per ride,
  named `<ISO8601 date>-<uuid>.json`. API: `save(recorder:date:) throws ->
  StoredRide`, `list() throws -> [StoredRide]` (sorted newest first),
  `delete(id:) throws`. Corrupt/unreadable files are skipped by `list()`
  (logged via `lastError`-style surface, not fatal) — DECISION: a broken
  file must never brick the History screen.
- **Saving** happens in `ContentView.endRide()` (and the auto-completion
  path) right where the recorder already stops: best-effort, failure shows
  in the summary sheet but never blocks it.
- **UI** — `GamePhase` gains `.history`, entered from a "History" button on
  `MenuView`, back to `.menu`. `HistoryView` lists rides with date,
  distance, duration, avg power; per-row: "Export TCX…" (`NSSavePanel` +
  `TCXExporter`, same flow as `RideSummaryView`) and delete (with
  confirmation). Empty state: a friendly "no rides yet".

## Testing

`RideStoreTests` against a temp directory: save→list roundtrip preserves
summary and samples; newest-first ordering; delete removes exactly one ride;
corrupt JSON file is skipped while healthy ones still list; re-exporting a
stored ride through `TCXExporter` equals the direct export of the original
recorder. UI stays untested per house convention.
