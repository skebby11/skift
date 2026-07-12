import XCTest
@testable import SkiftKit

final class StravaAPITests: XCTestCase {

    // MARK: - Authorization URL

    func testAuthorizationURLContainsExpectedQueryItems() throws {
        let url = StravaAPI.authorizationURL(
            clientID: "12345",
            redirectURI: "http://127.0.0.1:53219/callback"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.strava.com")
        XCTAssertEqual(components.path, "/oauth/authorize")

        let items = try XCTUnwrap(components.queryItems)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        XCTAssertEqual(byName["client_id"], "12345")
        XCTAssertEqual(byName["redirect_uri"], "http://127.0.0.1:53219/callback")
        XCTAssertEqual(byName["response_type"], "code")
        XCTAssertEqual(byName["scope"], "activity:write")
        XCTAssertEqual(byName["approval_prompt"], "auto")
    }

    // MARK: - Token exchange

    func testTokenExchangeRequestIsFormEncodedPOST() throws {
        let request = StravaAPI.tokenExchangeRequest(
            clientID: "12345",
            clientSecret: "s3cr3t",
            code: "abc123"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, URL(string: "https://www.strava.com/oauth/token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let body = try XCTUnwrap(request.httpBody)
        let form = try XCTUnwrap(formFields(from: body))
        XCTAssertEqual(form["client_id"], "12345")
        XCTAssertEqual(form["client_secret"], "s3cr3t")
        XCTAssertEqual(form["code"], "abc123")
        XCTAssertEqual(form["grant_type"], "authorization_code")
    }

    // MARK: - Token refresh

    func testTokenRefreshRequestIsFormEncodedPOST() throws {
        let request = StravaAPI.tokenRefreshRequest(
            clientID: "12345",
            clientSecret: "s3cr3t",
            refreshToken: "refresh-xyz"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, URL(string: "https://www.strava.com/oauth/token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let body = try XCTUnwrap(request.httpBody)
        let form = try XCTUnwrap(formFields(from: body))
        XCTAssertEqual(form["client_id"], "12345")
        XCTAssertEqual(form["client_secret"], "s3cr3t")
        XCTAssertEqual(form["refresh_token"], "refresh-xyz")
        XCTAssertEqual(form["grant_type"], "refresh_token")
    }

    // MARK: - Upload request (byte-exact multipart)

    func testUploadRequestProducesByteExactMultipartBody() throws {
        let tcx = "<TrainingCenterDatabase/>".data(using: .utf8)!
        let request = StravaAPI.uploadRequest(
            accessToken: "token-abc",
            tcxData: tcx,
            name: "Morning ride",
            boundary: "TEST-BOUNDARY"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, URL(string: "https://www.strava.com/api/v3/uploads"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-abc")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=TEST-BOUNDARY"
        )

        let expected =
            "--TEST-BOUNDARY\r\n" +
            "Content-Disposition: form-data; name=\"data_type\"\r\n\r\n" +
            "tcx\r\n" +
            "--TEST-BOUNDARY\r\n" +
            "Content-Disposition: form-data; name=\"trainer\"\r\n\r\n" +
            "1\r\n" +
            "--TEST-BOUNDARY\r\n" +
            "Content-Disposition: form-data; name=\"activity_type\"\r\n\r\n" +
            "VirtualRide\r\n" +
            "--TEST-BOUNDARY\r\n" +
            "Content-Disposition: form-data; name=\"name\"\r\n\r\n" +
            "Morning ride\r\n" +
            "--TEST-BOUNDARY\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"ride.tcx\"\r\n" +
            "Content-Type: application/octet-stream\r\n\r\n" +
            "<TrainingCenterDatabase/>\r\n" +
            "--TEST-BOUNDARY--\r\n"

        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(body, expected.data(using: .utf8))
    }

    // MARK: - Upload status request

    func testUploadStatusRequestIsAuthenticatedGET() throws {
        let request = StravaAPI.uploadStatusRequest(accessToken: "token-abc", uploadID: 987654)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url, URL(string: "https://www.strava.com/api/v3/uploads/987654"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-abc")
    }

    // MARK: - TokenResponse decoding

    func testTokenResponseDecodesRequiredFields() throws {
        let json = """
        {
            "access_token": "access-1",
            "refresh_token": "refresh-1",
            "expires_at": 1750003600
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        XCTAssertEqual(response.accessToken, "access-1")
        XCTAssertEqual(response.refreshToken, "refresh-1")
        XCTAssertEqual(response.expiresAt, 1_750_003_600)
        XCTAssertNil(response.athlete)
    }

    func testTokenResponseDecodesEmbeddedAthlete() throws {
        let json = """
        {
            "access_token": "access-1",
            "refresh_token": "refresh-1",
            "expires_at": 1750003600,
            "athlete": { "firstname": "Ada", "lastname": "Lovelace" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        XCTAssertEqual(response.athlete?.firstname, "Ada")
        XCTAssertEqual(response.athlete?.lastname, "Lovelace")
    }

    // MARK: - UploadStatus decoding + state

    func testUploadStatusProcessingFixture() throws {
        let json = """
        { "id": 1, "external_id": "skift-1", "status": "Your activity is still being processed." }
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(UploadStatus.self, from: json)
        XCTAssertEqual(status.state, .processing)
    }

    func testUploadStatusReadyFixture() throws {
        let json = """
        { "id": 1, "status": "Your activity is ready.", "activity_id": 42 }
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(UploadStatus.self, from: json)
        XCTAssertEqual(status.state, .ready(activityID: 42))
    }

    func testUploadStatusErrorFixture() throws {
        let json = """
        { "id": 1, "status": "There was an error processing your activity.", "error": "file is invalid" }
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(UploadStatus.self, from: json)
        XCTAssertEqual(status.state, .failed(message: "file is invalid"))
    }

    func testUploadStatusDuplicateFixtureParsesActivityID() throws {
        let json = """
        { "id": 1, "status": "There was an error processing your activity.", "error": "duplicate of activity 998877" }
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(UploadStatus.self, from: json)
        XCTAssertEqual(status.state, .duplicate(activityID: 998_877))
    }

    // MARK: - StravaTokens expiry

    func testIsExpiredFalseWellBeforeExpiry() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let now = Date(timeIntervalSince1970: 1_000_000 - 3600) // 1h before expiry
        XCTAssertFalse(tokens.isExpired(now: now))
    }

    func testIsExpiredTrueWithinFiveMinuteMargin() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let now = Date(timeIntervalSince1970: 1_000_000 - 60) // 1 minute before expiry
        XCTAssertTrue(tokens.isExpired(now: now))
    }

    func testIsExpiredTrueExactlyAtMargin() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let now = Date(timeIntervalSince1970: 1_000_000 - 300) // exactly 5 minutes before
        XCTAssertTrue(tokens.isExpired(now: now))
    }

    func testIsExpiredTrueAfterExpiry() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let now = Date(timeIntervalSince1970: 1_000_100)
        XCTAssertTrue(tokens.isExpired(now: now))
    }

    // MARK: - Helpers

    private func formFields(from body: Data) -> [String: String]? {
        guard let string = String(data: body, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).replacingOccurrences(of: "+", with: " ")
            result[key] = value.removingPercentEncoding ?? value
        }
        return result
    }
}
