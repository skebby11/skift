import Foundation

/// Pure request builders and response parsers for Strava's OAuth2 + Upload
/// API. No networking here — `StravaAccount` (app target) owns the
/// `URLSession` calls; everything in this file is a deterministic function
/// of its inputs, so it's fully unit-testable (see docs/strava-upload.md).
public enum StravaAPI {

    // MARK: - OAuth

    /// Builds the browser-facing authorization URL. Opened via `NSWorkspace`
    /// by `StravaAccount`; the loopback listener captures the resulting
    /// `code` on the redirect.
    public static func authorizationURL(clientID: String, redirectURI: String) -> URL {
        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "activity:write"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
        ]
        return components.url!
    }

    /// Exchanges the authorization `code` from the redirect for tokens.
    public static func tokenExchangeRequest(clientID: String, clientSecret: String, code: String) -> URLRequest {
        formEncodedRequest(fields: [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
        ])
    }

    /// Refreshes an expired (or about-to-expire) access token.
    public static func tokenRefreshRequest(clientID: String, clientSecret: String, refreshToken: String) -> URLRequest {
        formEncodedRequest(fields: [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    private static func formEncodedRequest(fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = fields
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        return request
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
    }

    // MARK: - Upload

    /// Builds the multipart upload request. `boundary` is injected so tests
    /// can assert a byte-exact body; production callers should pass a
    /// freshly generated UUID string.
    public static func uploadRequest(
        accessToken: String,
        tcxData: Data,
        name: String,
        boundary: String
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("data_type", "tcx")
        appendField("trainer", "1")
        appendField("activity_type", "VirtualRide")
        appendField("name", name)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"ride.tcx\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(tcxData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return request
    }

    /// Polls the status of a previously submitted upload.
    public static func uploadStatusRequest(accessToken: String, uploadID: Int64) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(uploadID)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

private extension CharacterSet {
    /// `application/x-www-form-urlencoded` value encoding: alphanumerics
    /// pass through untouched, everything else (including `+` and `&`) is
    /// percent-escaped so form fields round-trip exactly.
    static let urlQueryValueAllowed = CharacterSet.alphanumerics
}

// MARK: - Response models

/// Strava's OAuth token response. Strava also embeds a short `athlete`
/// summary in the token-exchange response (not on refresh) — captured here
/// so `StravaAccount` can show a name without a separate API call.
public struct TokenResponse: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Int64
    public let athlete: Athlete?

    public struct Athlete: Codable, Equatable {
        public let firstname: String?
        public let lastname: String?

        public init(firstname: String?, lastname: String?) {
            self.firstname = firstname
            self.lastname = lastname
        }
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }

    public init(accessToken: String, refreshToken: String, expiresAt: Int64, athlete: Athlete? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.athlete = athlete
    }
}

/// Strava's upload-status payload. `state` interprets the raw `status`
/// string plus the optional `error`/`activity_id` fields into the four
/// outcomes callers actually branch on.
public struct UploadStatus: Codable, Equatable {
    public let id: Int64
    public let status: String
    public let activityId: Int64?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case activityId = "activity_id"
        case error
    }

    public init(id: Int64, status: String, activityId: Int64? = nil, error: String? = nil) {
        self.id = id
        self.status = status
        self.activityId = activityId
        self.error = error
    }

    public enum State: Equatable {
        case processing
        case ready(activityID: Int64)
        case duplicate(activityID: Int64)
        case failed(message: String)
    }

    /// Strava reports a duplicate upload as an error whose message embeds
    /// the existing activity's id ("duplicate of activity 998877"); the
    /// spec treats that as a success-with-link rather than a failure.
    public var state: State {
        if let error, !error.isEmpty {
            if let activityID = Self.duplicateActivityID(from: error) {
                return .duplicate(activityID: activityID)
            }
            return .failed(message: error)
        }
        if let activityId {
            return .ready(activityID: activityId)
        }
        return .processing
    }

    private static func duplicateActivityID(from error: String) -> Int64? {
        guard let range = error.range(of: "duplicate of activity ") else { return nil }
        let digits = error[range.upperBound...].prefix(while: \.isNumber)
        return Int64(digits)
    }
}

/// Access/refresh/expiry triple, persisted in Keychain by `StravaAccount`.
public struct StravaTokens: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True once within 5 minutes of expiry (Strava access tokens last 6h) —
    /// refreshing early avoids racing a request against expiry mid-flight.
    public func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt.addingTimeInterval(-300)
    }
}
