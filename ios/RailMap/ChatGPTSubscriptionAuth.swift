import Foundation
import Observation
import Security

/// Device-code authentication for the experimental Codex subscription interface.
///
/// This openly uses Codex's public OAuth client identifier for protocol compatibility while
/// retaining URLSession's own user agent. Callers should describe the integration as experimental.
/// The ID token is decoded only for account labels; authorization comes from the access token.
@MainActor
@Observable
final class ChatGPTSubscriptionAuth {
    static let shared = ChatGPTSubscriptionAuth()

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let userCodeURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
    private static let deviceTokenURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
    private static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let redirectURI = "https://auth.openai.com/deviceauth/callback"
    private static let loginTimeout: Duration = .seconds(15 * 60)
    private static let refreshLeeway: TimeInterval = 300

    private(set) var accountLabel: String?
    private(set) var planLabel: String?
    private(set) var isSignedIn = false
    private(set) var userCode: String?
    let loginURL = URL(string: "https://auth.openai.com/codex/device")!
    private(set) var isSigningIn = false

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let storage: any ChatGPTSubscriptionCredentialStoring
    @ObservationIgnored private var credentials: StoredCredentials?
    @ObservationIgnored private var loginTask: Task<Void, Error>?
    @ObservationIgnored private var refreshTask: Task<StoredCredentials, Error>?
    @ObservationIgnored private var refreshTaskID: UUID?
    @ObservationIgnored private var loginGeneration: UInt64 = 0
    @ObservationIgnored private var credentialGeneration: UInt64 = 0

    convenience init() {
        self.init(
            session: Self.makeEphemeralURLSession(),
            storage: ChatGPTSubscriptionKeychainStorage()
        )
    }

    /// Internal injection point for URLProtocol-backed networking and in-memory storage tests.
    init(
        session: URLSession,
        storage: any ChatGPTSubscriptionCredentialStoring
    ) {
        self.session = session
        self.storage = storage

        if let data = try? storage.load(),
           let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data),
           !stored.accessToken.isEmpty,
           !stored.refreshToken.isEmpty,
           !stored.accountID.isEmpty {
            credentials = stored
            applyDisplayState(stored)
        }
    }

    /// A cookie-free, cache-free session that never follows HTTP redirects.
    /// The request client can use the same helper for subscription API calls.
    nonisolated static func makeEphemeralURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(
            configuration: configuration,
            delegate: ChatGPTSubscriptionNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    /// Requests a device code, waits for browser authorization, exchanges the code, and stores
    /// the resulting credentials in this app's device-only Keychain item.
    func login() async throws {
        cancelLogin()
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID = nil

        credentialGeneration &+= 1
        loginGeneration &+= 1
        let loginGeneration = loginGeneration
        let credentialGeneration = credentialGeneration

        isSigningIn = true
        userCode = nil

        let task = Task { @MainActor [self] in
            try await performLogin(
                loginGeneration: loginGeneration,
                credentialGeneration: credentialGeneration
            )
        }
        loginTask = task

        defer {
            if self.loginGeneration == loginGeneration {
                loginTask = nil
                isSigningIn = false
                userCode = nil
            }
        }

        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancelLogin() {
        loginGeneration &+= 1
        loginTask?.cancel()
        loginTask = nil
        userCode = nil
        isSigningIn = false
    }

    func signOut() throws {
        loginGeneration &+= 1
        credentialGeneration &+= 1
        loginTask?.cancel()
        refreshTask?.cancel()
        loginTask = nil
        refreshTask = nil
        refreshTaskID = nil
        userCode = nil
        isSigningIn = false

        try storage.delete()
        credentials = nil
        accountLabel = nil
        planLabel = nil
        isSignedIn = false
    }

    /// Returns a current bearer token and the account ID asserted by that access token.
    /// Concurrent refresh requests share one token request.
    func accessCredentials(forceRefresh: Bool = false) async throws -> (
        accessToken: String,
        accountID: String
    ) {
        guard let current = credentials else {
            throw AuthError.signedOut
        }

        if !forceRefresh,
           current.expiresAt.timeIntervalSinceNow > Self.refreshLeeway {
            return (current.accessToken, current.accountID)
        }

        let refreshed = try await refreshCredentials(from: current)
        return (refreshed.accessToken, refreshed.accountID)
    }

    private func performLogin(
        loginGeneration: UInt64,
        credentialGeneration: UInt64
    ) async throws {
        let deviceCode: DeviceCodeResponse = try await postJSON(
            to: Self.userCodeURL,
            body: UserCodeRequest(clientID: Self.clientID),
            operation: .requestCode
        )
        try Task.checkCancellation()
        try requireCurrentLogin(loginGeneration, credentialGeneration)

        let code = deviceCode.userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !deviceCode.deviceAuthID.isEmpty else {
            throw AuthError.invalidResponse(.requestCode)
        }
        userCode = code

        let authorization = try await pollForAuthorization(
            deviceAuthID: deviceCode.deviceAuthID,
            userCode: code,
            interval: max(1, deviceCode.interval)
        )
        try Task.checkCancellation()
        try requireCurrentLogin(loginGeneration, credentialGeneration)

        let token: TokenResponse = try await postForm(
            to: Self.tokenURL,
            fields: [
                "grant_type": "authorization_code",
                "client_id": Self.clientID,
                "code": authorization.authorizationCode,
                "redirect_uri": Self.redirectURI,
                "code_verifier": authorization.codeVerifier,
            ],
            operation: .exchangeCode
        )

        let stored = try makeCredentials(from: token, preserving: nil)
        try Task.checkCancellation()
        try requireCurrentLogin(loginGeneration, credentialGeneration)
        try persist(stored)
        try requireCurrentLogin(loginGeneration, credentialGeneration)
        credentials = stored
        applyDisplayState(stored)
    }

    private func pollForAuthorization(
        deviceAuthID: String,
        userCode: String,
        interval: Int
    ) async throws -> DeviceAuthorizationResponse {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.loginTimeout)

        while clock.now < deadline {
            try Task.checkCancellation()
            var request = URLRequest(url: Self.deviceTokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(
                DeviceTokenRequest(deviceAuthID: deviceAuthID, userCode: userCode)
            )

            let (data, response) = try await send(request, operation: .poll)
            if response.statusCode == 403 || response.statusCode == 404 {
                let wake = min(deadline, clock.now.advanced(by: .seconds(interval)))
                try await clock.sleep(until: wake)
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                throw AuthError.httpFailure(.poll, response.statusCode)
            }
            do {
                return try JSONDecoder().decode(DeviceAuthorizationResponse.self, from: data)
            } catch {
                throw AuthError.invalidResponse(.poll)
            }
        }

        throw AuthError.timedOut
    }

    private func refreshCredentials(from current: StoredCredentials) async throws -> StoredCredentials {
        if let refreshTask, let refreshTaskID {
            return try await awaitRefresh(refreshTask, id: refreshTaskID)
        }

        let generation = credentialGeneration
        let taskID = UUID()
        let task = Task { @MainActor [self] in
            let token: TokenResponse
            do {
                token = try await postJSON(
                    to: Self.tokenURL,
                    body: RefreshTokenRequest(clientID: Self.clientID, refreshToken: current.refreshToken),
                    operation: .refresh,
                    classifyFailure: Self.permanentRefreshFailure
                )
            } catch let error as AuthError {
                if case .sessionExpired = error, credentialGeneration == generation {
                    try? storage.delete()
                    credentials = nil
                    accountLabel = nil
                    planLabel = nil
                    isSignedIn = false
                    credentialGeneration &+= 1
                }
                throw error
            }

            let stored = try makeCredentials(from: token, preserving: current)
            guard credentialGeneration == generation else {
                throw CancellationError()
            }
            do {
                try persist(stored)
            } catch {
                // The refresh token in `stored` has already rotated server-side and is
                // single-use, so keep it in memory for this app run even if it could not
                // be written to storage.
                credentials = stored
                applyDisplayState(stored)
                throw error
            }
            credentials = stored
            applyDisplayState(stored)
            return stored
        }
        refreshTask = task
        refreshTaskID = taskID
        return try await awaitRefresh(task, id: taskID)
    }

    private func awaitRefresh(
        _ task: Task<StoredCredentials, Error>,
        id: UUID
    ) async throws -> StoredCredentials {
        defer {
            if refreshTaskID == id {
                refreshTask = nil
                refreshTaskID = nil
            }
        }
        // Refresh tokens are single-use. Do not cancel the shared refresh task if this
        // particular caller is cancelled; let it run to completion so the rotated token
        // is always persisted, and only surface cancellation to this caller afterward.
        let credentials = try await task.value
        try Task.checkCancellation()
        return credentials
    }

    private func requireCurrentLogin(
        _ loginGeneration: UInt64,
        _ credentialGeneration: UInt64
    ) throws {
        guard self.loginGeneration == loginGeneration,
              self.credentialGeneration == credentialGeneration else {
            throw CancellationError()
        }
    }

    private func postJSON<Request: Encodable, Response: Decodable>(
        to url: URL,
        body: Request,
        operation: AuthOperation,
        classifyFailure: ((Int, Data) -> AuthError?)? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await send(request, operation: operation)
        guard (200..<300).contains(response.statusCode) else {
            if let classifyFailure, let mapped = classifyFailure(response.statusCode, data) {
                throw mapped
            }
            if operation == .requestCode, response.statusCode == 404 {
                throw AuthError.deviceAuthorizationUnavailable
            }
            throw AuthError.httpFailure(operation, response.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthError.invalidResponse(operation)
        }
    }

    private func postForm<Response: Decodable>(
        to url: URL,
        fields: [String: String],
        operation: AuthOperation
    ) async throws -> Response {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        // URLComponents leaves literal "+" characters intact, but form decoders interpret them
        // as spaces. Encode them explicitly so authorization codes and refresh tokens round-trip.
        guard let encoded = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B"),
              let body = encoded.data(using: .utf8) else {
            throw AuthError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        let (data, response) = try await send(request, operation: operation)
        guard (200..<300).contains(response.statusCode) else {
            throw AuthError.httpFailure(operation, response.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthError.invalidResponse(operation)
        }
    }

    private func send(
        _ request: URLRequest,
        operation: AuthOperation
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse(operation)
            }
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AuthError {
            throw error
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw AuthError.networkFailure(operation)
        }
    }

    private func makeCredentials(
        from token: TokenResponse,
        preserving existing: StoredCredentials?
    ) throws -> StoredCredentials {
        let accessToken = token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw AuthError.invalidResponse(existing == nil ? .exchangeCode : .refresh)
        }

        let accessClaims = try Self.jwtClaims(accessToken)
        guard let expiresAt = Self.expirationDate(from: accessClaims),
              let accountID = Self.stringClaim("chatgpt_account_id", in: accessClaims),
              !accountID.isEmpty else {
            throw AuthError.missingAccessTokenClaims
        }

        let refreshToken = token.refreshToken ?? existing?.refreshToken
        guard let refreshToken, !refreshToken.isEmpty else {
            throw AuthError.missingRefreshToken
        }

        let idToken = token.idToken ?? existing?.idToken
        var email = existing?.email
        var plan = existing?.plan
        if let idToken, let idClaims = try? Self.jwtClaims(idToken) {
            email = Self.stringClaim("email", in: idClaims) ?? email
            plan = Self.stringClaim("chatgpt_plan_type", in: idClaims) ?? plan
        }

        return StoredCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: expiresAt,
            accountID: accountID,
            email: email,
            plan: plan
        )
    }

    private func persist(_ credentials: StoredCredentials) throws {
        do {
            try storage.save(JSONEncoder().encode(credentials))
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.secureStorageFailure(nil)
        }
    }

    private func applyDisplayState(_ credentials: StoredCredentials) {
        accountLabel = credentials.email ?? credentials.accountID
        planLabel = Self.displayPlan(credentials.plan)
        isSignedIn = true
    }

    nonisolated private static func jwtClaims(_ token: String) throws -> [String: Any] {
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else {
            throw AuthError.missingAccessTokenClaims
        }
        var encoded = String(components[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder != 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: encoded),
              let claims = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.missingAccessTokenClaims
        }
        return claims
    }

    nonisolated private static func expirationDate(from claims: [String: Any]) -> Date? {
        if let value = claims["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        if let value = claims["exp"] as? String, let seconds = TimeInterval(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    nonisolated private static func stringClaim(
        _ name: String,
        in claims: [String: Any]
    ) -> String? {
        if let value = claims[name] as? String, !value.isEmpty {
            return value
        }
        for namespace in ["https://api.openai.com/auth", "https://api.openai.com/profile"] {
            if let nested = claims[namespace] as? [String: Any],
               let value = nested[name] as? String,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Classifies a non-2xx refresh response as a permanent failure that requires signing in
    /// again, or `nil` to fall back to the generic transient `httpFailure`.
    nonisolated private static func permanentRefreshFailure(status: Int, body: Data) -> AuthError? {
        let code = refreshErrorCode(from: body)
        switch code {
        case "refresh_token_expired":
            return .sessionExpired("Your refresh token has expired. Sign in again.")
        case "refresh_token_reused":
            return .sessionExpired("Your refresh token was already used. Sign in again.")
        case "refresh_token_invalidated":
            return .sessionExpired("Your refresh token was revoked. Sign in again.")
        default:
            break
        }
        if status == 401 {
            return .sessionExpired("Your ChatGPT session can no longer be refreshed. Sign in again.")
        }
        if status == 400, code == "invalid_grant" {
            return .sessionExpired("Your ChatGPT session can no longer be refreshed. Sign in again.")
        }
        return nil
    }

    nonisolated private static func refreshErrorCode(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        if let code = json["error"] as? String {
            return code
        }
        if let error = json["error"] as? [String: Any] {
            return (error["code"] as? String) ?? (error["type"] as? String)
        }
        return nil
    }

    nonisolated private static func displayPlan(_ plan: String?) -> String? {
        guard let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines),
              !plan.isEmpty else { return nil }
        return switch plan.lowercased() {
        case "free": "Free"
        case "plus": "Plus"
        case "pro": "Pro"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        case "edu": "Edu"
        default: plan
        }
    }
}

extension ChatGPTSubscriptionAuth {
    enum AuthError: LocalizedError, Equatable {
        case signedOut
        case invalidRequest
        case networkFailure(AuthOperation)
        case httpFailure(AuthOperation, Int)
        case invalidResponse(AuthOperation)
        case deviceAuthorizationUnavailable
        case timedOut
        case missingAccessTokenClaims
        case missingRefreshToken
        case secureStorageFailure(OSStatus?)
        case sessionExpired(String)

        var errorDescription: String? {
            switch self {
            case .signedOut:
                "Sign in with ChatGPT to continue."
            case .invalidRequest:
                "The sign-in request could not be created."
            case .networkFailure(let operation):
                "ChatGPT sign-in could not complete during \(operation.label). Check your connection and try again."
            case .httpFailure(let operation, let status):
                "ChatGPT sign-in failed during \(operation.label) (HTTP \(status))."
            case .invalidResponse(let operation):
                "ChatGPT returned an invalid response during \(operation.label)."
            case .deviceAuthorizationUnavailable:
                "ChatGPT device authorization is not available."
            case .timedOut:
                "ChatGPT sign-in expired after 15 minutes."
            case .missingAccessTokenClaims:
                "ChatGPT returned credentials without the required account information."
            case .missingRefreshToken:
                "ChatGPT returned credentials that cannot be refreshed."
            case .secureStorageFailure(let status):
                if let status {
                    "Credentials could not be stored securely (Keychain status \(status))."
                } else {
                    "Credentials could not be stored securely."
                }
            case .sessionExpired(let message):
                message
            }
        }
    }

    enum AuthOperation: String, Equatable, Sendable {
        case requestCode
        case poll
        case exchangeCode
        case refresh

        fileprivate var label: String {
            switch self {
            case .requestCode: "device-code request"
            case .poll: "authorization"
            case .exchangeCode: "token exchange"
            case .refresh: "token refresh"
            }
        }
    }
}

protocol ChatGPTSubscriptionCredentialStoring {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

private struct ChatGPTSubscriptionKeychainStorage: ChatGPTSubscriptionCredentialStoring {
    private let service = "com.JRM.RailMap.chatgpt-subscription"
    private let account = "oauth-credentials"

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ChatGPTSubscriptionAuth.AuthError.secureStorageFailure(status)
        }
        guard let data = result as? Data else {
            throw ChatGPTSubscriptionAuth.AuthError.secureStorageFailure(nil)
        }
        return data
    }

    func save(_ data: Data) throws {
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw ChatGPTSubscriptionAuth.AuthError.secureStorageFailure(updateStatus)
            }
        } else if status != errSecSuccess {
            throw ChatGPTSubscriptionAuth.AuthError.secureStorageFailure(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ChatGPTSubscriptionAuth.AuthError.secureStorageFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

private final class ChatGPTSubscriptionNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct StoredCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let expiresAt: Date
    let accountID: String
    let email: String?
    let plan: String?
}

private struct UserCodeRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct RefreshTokenRequest: Encodable {
    let clientID: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientID = "client_id"
        case refreshToken = "refresh_token"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("refresh_token", forKey: .grantType)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(refreshToken, forKey: .refreshToken)
    }
}

private struct DeviceCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case usercode
        case interval
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try values.decode(String.self, forKey: .deviceAuthID)
        userCode = try values.decodeIfPresent(String.self, forKey: .userCode)
            ?? values.decode(String.self, forKey: .usercode)
        if !values.contains(.interval) {
            interval = 1
        } else if let integer = try? values.decode(Int.self, forKey: .interval) {
            interval = integer
        } else {
            let string = try values.decode(String.self, forKey: .interval)
            guard let integer = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .interval,
                    in: values,
                    debugDescription: "Expected an integer interval."
                )
            }
            interval = integer
        }
    }
}

private struct DeviceTokenRequest: Encodable {
    let deviceAuthID: String
    let userCode: String

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
    }
}

private struct DeviceAuthorizationResponse: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}
