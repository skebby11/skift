import AppKit
import Foundation
import Network
import SkiftKit
import SwiftUI

/// Everything that can go wrong between "Connect Strava…" and a finished
/// upload, with user-facing messages (surfaced inline, never blocking —
/// docs/strava-upload.md "Error handling").
enum StravaError: LocalizedError {
    case notConnected
    case missingCredentials
    case authorizationFailed(String)
    case httpError(Int, String)
    case uploadFailed(String)
    case uploadTimedOut

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Strava — connect in Settings first."
        case .missingCredentials:
            return "Enter your Strava API client ID and secret in Settings first."
        case let .authorizationFailed(message):
            return "Strava authorization failed: \(message)"
        case let .httpError(code, message):
            return "Strava returned an error (HTTP \(code)): \(message)"
        case let .uploadFailed(message):
            return "Upload failed: \(message)"
        case .uploadTimedOut:
            return "Strava is still processing the upload — check your Strava feed in a minute."
        }
    }
}

/// Orchestrates the Strava connection: OAuth authorization-code flow with a
/// one-shot loopback listener, Keychain persistence for the client secret +
/// tokens, transparent token refresh, and TCX upload with status polling.
///
/// All the request building and response parsing is pure `StravaAPI`
/// (SkiftKit, unit-tested); this class owns only the I/O — `URLSession`,
/// `NWListener`, `NSWorkspace`, Keychain (see docs/strava-upload.md).
@MainActor
final class StravaAccount: ObservableObject {

    @Published private(set) var isConnected = false
    @Published private(set) var athleteName: String?
    @Published private(set) var uploadInProgress = false

    /// The client ID is public (it appears in the authorization URL), so
    /// plain `@AppStorage` is fine; the secret and tokens live in Keychain.
    @AppStorage(RiderSettings.stravaClientIDKey)
    var clientID: String = ""

    private enum KeychainAccount {
        static let clientSecret = "client-secret"
        static let tokens = "tokens"
        static let athleteName = "athlete-name"
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        // Restore the persisted connection on launch.
        isConnected = loadTokens() != nil
        athleteName = KeychainStore.string(account: KeychainAccount.athleteName)
    }

    // MARK: - Credentials

    var clientSecret: String {
        get { KeychainStore.string(account: KeychainAccount.clientSecret) ?? "" }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(account: KeychainAccount.clientSecret)
            } else {
                KeychainStore.setString(newValue, account: KeychainAccount.clientSecret)
            }
        }
    }

    private var hasCredentials: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    // MARK: - Tokens (Keychain)

    private func loadTokens() -> StravaTokens? {
        guard let data = KeychainStore.data(account: KeychainAccount.tokens) else { return nil }
        return try? JSONDecoder().decode(StravaTokens.self, from: data)
    }

    private func storeTokens(_ tokens: StravaTokens) {
        if let data = try? JSONEncoder().encode(tokens) {
            KeychainStore.setData(data, account: KeychainAccount.tokens)
        }
        isConnected = true
    }

    // MARK: - Connect / disconnect

    /// Runs the whole OAuth authorization-code flow: starts the loopback
    /// listener, opens the browser at Strava's authorize page, waits for the
    /// redirect to deliver `code`, exchanges it for tokens, persists them.
    func connect() async throws {
        guard hasCredentials else { throw StravaError.missingCredentials }

        let callback = try LoopbackCallbackServer()
        defer { callback.stop() }

        let authorizeURL = StravaAPI.authorizationURL(
            clientID: clientID,
            redirectURI: "http://127.0.0.1:\(callback.port)/callback"
        )
        NSWorkspace.shared.open(authorizeURL)

        let code = try await callback.waitForCode()

        let request = StravaAPI.tokenExchangeRequest(
            clientID: clientID,
            clientSecret: clientSecret,
            code: code
        )
        let response = try await performTokenRequest(request)

        // Strava embeds a short athlete blob in the token-exchange response;
        // remember the name for the Settings status line (persisted so it
        // survives relaunch — refresh responses don't include it).
        let name = [response.athlete?.firstname, response.athlete?.lastname]
            .compactMap { $0 }
            .joined(separator: " ")
        if !name.isEmpty {
            athleteName = name
            KeychainStore.setString(name, account: KeychainAccount.athleteName)
        }
    }

    /// Forgets the Strava connection: tokens and athlete name are wiped from
    /// Keychain. The client ID/secret stay — disconnecting isn't "delete my
    /// API app credentials".
    func disconnect() {
        KeychainStore.delete(account: KeychainAccount.tokens)
        KeychainStore.delete(account: KeychainAccount.athleteName)
        isConnected = false
        athleteName = nil
    }

    // MARK: - Upload

    /// Uploads a TCX payload as a VirtualRide and polls until Strava finishes
    /// processing. Returns the resulting activity id (a duplicate upload
    /// resolves to the EXISTING activity's id — success-with-link per
    /// docs/strava-upload.md "Error handling").
    func upload(tcxData: Data, name: String) async throws -> Int64 {
        guard isConnected else { throw StravaError.notConnected }

        uploadInProgress = true
        defer { uploadInProgress = false }

        var accessToken = try await validAccessToken()

        // Submit the upload; one refresh-and-retry on 401 covers a token
        // revoked-and-reissued outside our expiry bookkeeping.
        var (data, http) = try await perform(StravaAPI.uploadRequest(
            accessToken: accessToken, tcxData: tcxData, name: name, boundary: UUID().uuidString
        ))
        if http.statusCode == 401 {
            accessToken = try await refreshedAccessToken()
            (data, http) = try await perform(StravaAPI.uploadRequest(
                accessToken: accessToken, tcxData: tcxData, name: name, boundary: UUID().uuidString
            ))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StravaError.httpError(http.statusCode, Self.errorMessage(from: data))
        }
        var status = try JSONDecoder().decode(UploadStatus.self, from: data)

        // Poll every 2 s until processed, ~30 s cap (docs/strava-upload.md).
        for _ in 0..<15 {
            switch status.state {
            case let .ready(activityID), let .duplicate(activityID):
                return activityID
            case let .failed(message):
                throw StravaError.uploadFailed(message)
            case .processing:
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let (pollData, pollHTTP) = try await perform(
                    StravaAPI.uploadStatusRequest(accessToken: accessToken, uploadID: status.id)
                )
                guard (200..<300).contains(pollHTTP.statusCode) else {
                    throw StravaError.httpError(pollHTTP.statusCode, Self.errorMessage(from: pollData))
                }
                status = try JSONDecoder().decode(UploadStatus.self, from: pollData)
            }
        }
        // Final check after the loop so a status that resolved on the last
        // poll isn't reported as a timeout.
        switch status.state {
        case let .ready(activityID), let .duplicate(activityID):
            return activityID
        case let .failed(message):
            throw StravaError.uploadFailed(message)
        case .processing:
            throw StravaError.uploadTimedOut
        }
    }

    // MARK: - Token refresh

    /// Returns a usable access token, transparently refreshing when within
    /// the 5-minute expiry margin.
    private func validAccessToken() async throws -> String {
        guard let tokens = loadTokens() else { throw StravaError.notConnected }
        guard tokens.isExpired() else { return tokens.accessToken }
        return try await refreshedAccessToken()
    }

    private func refreshedAccessToken() async throws -> String {
        guard let tokens = loadTokens() else { throw StravaError.notConnected }
        guard hasCredentials else { throw StravaError.missingCredentials }
        let request = StravaAPI.tokenRefreshRequest(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: tokens.refreshToken
        )
        let response = try await performTokenRequest(request)
        return response.accessToken
    }

    /// Sends a token exchange/refresh request, decodes the response and
    /// persists the (rotated) tokens.
    private func performTokenRequest(_ request: URLRequest) async throws -> TokenResponse {
        let (data, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw StravaError.httpError(http.statusCode, Self.errorMessage(from: data))
        }
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(StravaTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(response.expiresAt))
        ))
        return response
    }

    // MARK: - HTTP plumbing

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.httpError(0, "Unexpected non-HTTP response.")
        }
        return (data, http)
    }

    /// Strava error bodies carry a top-level `message` field; fall back to
    /// the raw body (truncated) when they don't.
    private static func errorMessage(from data: Data) -> String {
        struct ErrorBody: Decodable { let message: String? }
        if let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message, !message.isEmpty {
            return message
        }
        return String(data: data.prefix(200), encoding: .utf8) ?? "no details"
    }
}

// MARK: - Loopback OAuth callback

/// One-shot HTTP listener on `127.0.0.1:<random port>` that serves the OAuth
/// redirect. Strava only accepts http(s) redirect URIs, so the user's API
/// app sets callback domain `127.0.0.1` and we catch the redirect locally
/// (docs/strava-upload.md, DECISION on loopback vs. URL schemes). Requires
/// the `com.apple.security.network.server` sandbox entitlement.
private final class LoopbackCallbackServer {

    let port: UInt16
    private let listener: NWListener
    private let delivery: CodeDelivery

    /// Thread-safe, resume-once holder for the waiting continuation. A
    /// separate reference type so the listener's connection handler can be
    /// installed during `init` without capturing a half-initialized `self`.
    private final class CodeDelivery {
        private var continuation: CheckedContinuation<String, Error>?
        private let lock = NSLock()

        func wait() async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
            }
        }

        /// Resumes the waiting continuation exactly once; later calls are
        /// no-ops (e.g. `stop()` running after the code was delivered).
        func resume(_ result: Result<String, Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            switch result {
            case let .success(code): continuation?.resume(returning: code)
            case let .failure(error): continuation?.resume(throwing: error)
            }
        }
    }

    init() throws {
        // Port 0 = let the kernel pick a free ephemeral port.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let delivery = CodeDelivery()
        listener.newConnectionHandler = { connection in
            Self.handle(connection, delivery: delivery)
        }
        listener.start(queue: .global(qos: .userInitiated))

        // The port is assigned during start; wait briefly (it's near-instant)
        // and surface a failure as a thrown error rather than a hang.
        var resolved: UInt16 = 0
        for _ in 0..<50 {
            if let p = listener.port?.rawValue, p != 0 {
                resolved = p
                break
            }
            usleep(10_000) // 10 ms
        }
        guard resolved != 0 else {
            listener.cancel()
            throw StravaError.authorizationFailed("couldn't open the local callback listener.")
        }

        self.listener = listener
        self.delivery = delivery
        self.port = resolved
    }

    func waitForCode() async throws -> String {
        try await delivery.wait()
    }

    func stop() {
        listener.cancel()
        delivery.resume(.failure(CancellationError()))
    }

    private static func handle(_ connection: NWConnection, delivery: CodeDelivery) {
        connection.start(queue: .global(qos: .userInitiated))
        // The redirect's GET line fits well within 8 KiB; we only need the
        // request line to read the query string.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let result = parseCallback(request)

            let html: String
            switch result {
            case .success:
                html = "<html><body style=\"font-family: -apple-system, sans-serif; text-align: center; padding-top: 4em;\"><h2>Connected to Strava</h2><p>You can return to Skift.</p></body></html>"
            case .failure:
                html = "<html><body style=\"font-family: -apple-system, sans-serif; text-align: center; padding-top: 4em;\"><h2>Authorization failed</h2><p>Return to Skift and try again.</p></body></html>"
            }
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"

            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
                // One-shot: first callback settles the flow either way.
                delivery.resume(result)
            })
        }
    }

    /// Extracts `code` from the callback request line
    /// (`GET /callback?state=&code=... HTTP/1.1`). An `error` parameter
    /// (user clicked Cancel on Strava's page) becomes a failure.
    private static func parseCallback(_ request: String) -> Result<String, Error> {
        guard let requestLine = request.components(separatedBy: "\r\n").first,
              requestLine.hasPrefix("GET "),
              let target = requestLine.components(separatedBy: " ").dropFirst().first,
              let components = URLComponents(string: target),
              components.path == "/callback"
        else {
            return .failure(StravaError.authorizationFailed("unexpected request on the callback listener."))
        }
        let items = components.queryItems ?? []
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return .success(code)
        }
        let error = items.first(where: { $0.name == "error" })?.value ?? "no authorization code returned"
        return .failure(StravaError.authorizationFailed(error))
    }
}
