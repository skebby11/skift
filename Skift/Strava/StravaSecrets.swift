import Foundation

/// Pre-provisioned Strava API credentials for login-only builds.
///
/// Skift is BYO-credentials by default (docs/strava-upload.md): each user
/// pastes their own Strava API app's Client ID/Secret in Settings, since a
/// shared secret can't be committed to this public Apache-2.0 repo. An owner
/// who wants a login-only build for their own distribution can instead drop
/// a gitignored `Skift/Secrets.plist` (see `Skift/Secrets.example.plist` for
/// the shape) with keys `StravaClientID` / `StravaClientSecret`; XcodeGen
/// bundles it as a resource automatically when present. `StravaAccount`
/// prefers these over user-entered credentials when both exist.
struct StravaSecrets {
    let clientID: String
    let clientSecret: String

    /// Reads `Secrets.plist` from the given bundle. Returns `nil` when the
    /// file is absent (the public/cloner case) or when either value is
    /// missing/empty — a half-provisioned file falls back to BYO rather than
    /// silently breaking `connect()`.
    static func bundled(bundle: Bundle = .main) -> StravaSecrets? {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        guard let clientID = plist["StravaClientID"] as? String, !clientID.isEmpty,
              let clientSecret = plist["StravaClientSecret"] as? String, !clientSecret.isEmpty
        else { return nil }

        return StravaSecrets(clientID: clientID, clientSecret: clientSecret)
    }
}
