# Strava direct upload (OAuth2 + Upload API)

*Design note, 2026-07-12. Replaces the "export a file, upload it by hand"
flow as the primary path; TCX export stays as the offline fallback.*

## Goal

One click (or zero, with auto-upload) from ride summary to a *VirtualRide*
activity on Strava. The user brings their own Strava API application
(https://www.strava.com/settings/api): Skift is open source, so no shared
client secret can ship with the app.

## Scope

In: connect/disconnect a Strava account (OAuth2 authorization-code flow),
upload a completed ride as TCX from the summary sheet and from history,
optional auto-upload on ride completion, upload status per stored ride
(remembered `activity_id`). Out: reading anything back from Strava (segments,
kudos, athlete stats), webhook de-authorization handling, photo/gear fields,
FIT upload.

## Architecture

Pure logic in `SkiftKit` (testable), all I/O in the app target:

- **`StravaAPI`** (SkiftKit, pure) — builds `URLRequest`s and parses
  responses, no networking: authorization URL (scope `activity:write`,
  `approval_prompt=auto`), token exchange + refresh request bodies, the
  multipart upload request (fields: `data_type=tcx`, `trainer=1`,
  `activity_type=VirtualRide`, `name`), upload-status polling request, and
  `Codable` models (`TokenResponse`, `UploadStatus` with its
  ready/processing/error states). Multipart boundary injected for
  deterministic tests.
- **`StravaTokens`** (SkiftKit, pure) — access/refresh/expiry value type with
  `isExpired(now:)` (5-minute early-refresh margin; Strava tokens last 6 h).
- **`StravaAccount`** (app target) — `ObservableObject` orchestrator:
  Keychain storage for client secret + tokens (client ID in `@AppStorage`),
  OAuth flow, `URLSession` calls via `StravaAPI`, transparent refresh,
  `upload(ride:)` with status polling (2 s interval, ~30 s cap).
- **OAuth callback** — Strava only accepts http(s) redirect URIs: a one-shot
  loopback listener (`NWListener` on `127.0.0.1`, random port) serves
  `http://127.0.0.1:<port>/callback`, captures `code`, answers a tiny
  "return to Skift" page, closes. The user's Strava app must set callback
  domain `127.0.0.1` (documented in Settings UI). Sandbox: add
  `com.apple.security.network.client` (API calls) and
  `com.apple.security.network.server` (loopback) to `project.yml`.
  DECISION: loopback over custom URL scheme — Strava rejects non-http
  schemes; over ASWebAuthenticationSession — it requires the callback
  scheme registered to the app, same constraint.

### Persistence

`StoredRide` gains optional `stravaActivityID: Int64?` (backward compatible —
old JSON decodes with nil). `RideStore` gains
`markUploaded(id:activityID:) throws`. History rows show an "On Strava"
badge instead of the upload button when set.

## UI

- **Settings → Strava**: Client ID + Client Secret fields (secret masked,
  stored in Keychain on commit), "Connect Strava…" / "Disconnect" button,
  "Auto-upload completed rides" toggle (off by default), connection status
  line with athlete name after connect.
- **RideSummaryView**: "Upload to Strava" button (visible only when
  connected) with progress spinner → success ("View on Strava" link) or
  inline error. Auto-upload triggers the same path on appear when the toggle
  is on and the ride was just saved.
- **HistoryView**: per-row upload button / "On Strava" badge.

## Error handling

Every failure is inline and non-blocking (summary sheet and history keep
working): HTTP errors surface Strava's `message`; a 401 on upload triggers
one refresh-and-retry, then surfaces; duplicate uploads surface Strava's
"duplicate of activity N" as success-with-link when the error body carries
the activity id.

## Testing

`StravaAPITests` (pure): authorization URL query items, token
exchange/refresh bodies, multipart body byte-exact with injected boundary,
`TokenResponse`/`UploadStatus` decoding (ready / processing / error /
duplicate fixtures), `StravaTokens.isExpired` margins. `RideStoreTests`:
`stravaActivityID` round-trip + old-JSON backward compat +
`markUploaded`. The OAuth loopback and real HTTP stay manual (REVIEW: verify
the full flow against the real Strava app once credentials are configured).

## Provisioned builds

BYO credentials stay the public default: Skift is open source, so no shared
client secret ships in this repo. An owner distributing their own build can
instead drop a gitignored `Skift/Secrets.plist` (keys `StravaClientID`,
`StravaClientSecret` — see `Skift/Secrets.example.plist` for the shape) next
to `Skift/Info.plist`; XcodeGen bundles it as a resource automatically when
present, and its absence doesn't affect generation or the build (the
CI/cloner case). `StravaSecrets.bundled()` reads it at runtime and
`StravaAccount` prefers it over user-entered credentials
(`usesBundledCredentials`); Settings then hides the Client ID/Secret fields
and shows only Connect/Disconnect. A hosted token-exchange proxy — so even
the loopback OAuth dance disappears — is a possible future upgrade, out of
scope for now.
