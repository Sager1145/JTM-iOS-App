#!/usr/bin/env python3
"""Exercise ChatGPT subscription auth with URLProtocol fixtures (no live login)."""

import os
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[2]
harness = r'''
import Foundation

final class MemoryStorage: ChatGPTSubscriptionCredentialStoring, @unchecked Sendable {
    enum Failure: Error { case requested }
    private let lock = NSLock()
    private var value: Data?
    private var deleteShouldFail = false

    func load() throws -> Data? { lock.withLock { value } }
    func save(_ data: Data) throws { lock.withLock { value = data } }
    func delete() throws {
        try lock.withLock {
            if deleteShouldFail { throw Failure.requested }
            value = nil
        }
    }
    func failDeletion(_ fail: Bool) { lock.withLock { deleteShouldFail = fail } }
    func isEmpty() -> Bool { lock.withLock { value == nil } }
}

final class ReplyGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() { semaphore.wait() }
    func release() { semaphore.signal() }
}

final class Fixtures: @unchecked Sendable {
    struct Reply: Sendable {
        let status: Int
        let body: String
        let gate: ReplyGate?
        init(status: Int, body: String, gate: ReplyGate? = nil) {
            self.status = status
            self.body = body
            self.gate = gate
        }
    }
    private let lock = NSLock()
    private var replies: [Reply] = []
    private var requests: [URLRequest] = []

    func set(_ values: [Reply]) { lock.withLock { replies = values; requests = [] } }
    func next(_ request: URLRequest) -> Reply {
        lock.withLock {
            requests.append(request)
            precondition(!replies.isEmpty, "Unexpected HTTP request")
            return replies.removeFirst()
        }
    }
    func recorded() -> [URLRequest] { lock.withLock { requests } }
}

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = Fixtures()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.fixtures.next(request)
        reply.gate?.wait()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func jwt(_ claims: [String: Any]) throws -> String {
    let header = try JSONSerialization.data(withJSONObject: ["alg": "none"])
    let payload = try JSONSerialization.data(withJSONObject: claims)
    return "\(base64URL(header)).\(base64URL(payload)).fixture"
}

func json(_ object: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

func requestBody(_ request: URLRequest) -> String {
    let bodyData: Data
    if let data = request.httpBody {
        bodyData = data
    } else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        bodyData = data
    } else {
        bodyData = Data()
    }
    return String(decoding: bodyData, as: UTF8.self)
}

func form(_ body: String) -> [String: String] {
    var components = URLComponents()
    components.percentEncodedQuery = body.replacingOccurrences(of: "+", with: "%20")
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
        guard let value = $0.value else { return nil }
        return ($0.name, value)
    })
}

@main struct Checks {
    @MainActor static func main() async throws {
        let expiration = Date().addingTimeInterval(3600).timeIntervalSince1970
        let access = try jwt([
            "exp": expiration,
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-fixture"],
        ])
        let refreshedAccess = try jwt([
            "exp": expiration + 60,
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-fixture"],
        ])
        let idToken = try jwt([
            "email": "rail@example.com",
            "https://api.openai.com/auth": ["chatgpt_plan_type": "plus"],
        ])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        let storage = MemoryStorage()
        let auth = ChatGPTSubscriptionAuth(session: session, storage: storage)
        let fixture = FixtureProtocol.fixtures

        fixture.set([
            .init(status: 200, body: #"{"device_auth_id":"device-fixture","user_code":"ABCD-EFGH","interval":"1"}"#),
            .init(status: 403, body: #"{"private":"pending"}"#),
            .init(status: 200, body: #"{"authorization_code":"authorization+fixture","code_verifier":"verifier+fixture","code_challenge":"unused"}"#),
            .init(status: 200, body: try json([
                "access_token": access, "refresh_token": "refresh+fixture", "id_token": idToken,
            ])),
        ])
        try await auth.login()
        precondition(auth.isSignedIn)
        precondition(auth.accountLabel == "rail@example.com")
        precondition(auth.planLabel == "Plus")
        precondition(auth.userCode == nil && !auth.isSigningIn)
        precondition(auth.loginURL.absoluteString == "https://auth.openai.com/codex/device")
        let current = try await auth.accessCredentials()
        precondition(current.accessToken == access && current.accountID == "acct-fixture")

        let loginRequests = fixture.recorded()
        precondition(loginRequests.count == 4)
        precondition(loginRequests.allSatisfy { $0.url?.scheme == "https" && $0.url?.host == "auth.openai.com" })
        precondition(loginRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        let exchangeBody = requestBody(loginRequests[3])
        let exchange = form(exchangeBody)
        precondition(exchangeBody.contains("code=authorization%2Bfixture"), exchangeBody)
        precondition(exchangeBody.contains("code_verifier=verifier%2Bfixture"), exchangeBody)
        precondition(exchange["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann", "\(exchange)")
        precondition(exchange["redirect_uri"] == "https://auth.openai.com/deviceauth/callback", "\(exchange)")
        precondition(exchange["code"] == "authorization+fixture", "\(exchange)")
        precondition(exchange["code_verifier"] == "verifier+fixture", "\(exchange)")

        fixture.set([
            .init(status: 200, body: try json(["access_token": refreshedAccess])),
        ])
        async let first = auth.accessCredentials(forceRefresh: true)
        async let second = auth.accessCredentials(forceRefresh: true)
        let (one, two) = try await (first, second)
        precondition(one.accessToken == refreshedAccess && two.accessToken == refreshedAccess)
        precondition(fixture.recorded().count == 1, "Concurrent refreshes were not coalesced")
        let refreshRequest = fixture.recorded()[0]
        precondition(refreshRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let refreshJSON = try JSONSerialization.jsonObject(
            with: Data(requestBody(refreshRequest).utf8), options: []
        ) as? [String: Any]
        precondition(refreshJSON?["grant_type"] as? String == "refresh_token", "\(String(describing: refreshJSON))")
        precondition(refreshJSON?["client_id"] as? String == "app_EMoamEEZ73f0CkXaXp7hrann")
        precondition(refreshJSON?["refresh_token"] as? String == "refresh+fixture", "\(String(describing: refreshJSON))")

        // A refresh permanently rejected (400 invalid_grant) must clear stored credentials and
        // surface a session-expired error, without retrying.
        fixture.set([
            .init(status: 400, body: #"{"error":"invalid_grant"}"#),
        ])
        do {
            _ = try await auth.accessCredentials(forceRefresh: true)
            preconditionFailure("Accepted permanently rejected refresh")
        } catch ChatGPTSubscriptionAuth.AuthError.sessionExpired {
            // expected
        }
        precondition(!auth.isSignedIn, "Permanent refresh failure must sign the user out")
        precondition(storage.isEmpty(), "Permanent refresh failure must clear stored credentials")
        do {
            _ = try await auth.accessCredentials()
            preconditionFailure("Returned credentials after a permanent refresh failure")
        } catch ChatGPTSubscriptionAuth.AuthError.signedOut { }

        // Sign back in so the cancellation-safety case below has current credentials to refresh.
        fixture.set([
            .init(status: 200, body: #"{"device_auth_id":"device-fixture-2","user_code":"IJKL-MNOP","interval":"1"}"#),
            .init(status: 200, body: #"{"authorization_code":"authorization+fixture-2","code_verifier":"verifier+fixture-2","code_challenge":"unused"}"#),
            .init(status: 200, body: try json([
                "access_token": access, "refresh_token": "refresh+rotated-1", "id_token": idToken,
            ])),
        ])
        try await auth.login()
        precondition(auth.isSignedIn)

        // A caller that is cancelled while a delayed refresh response is in flight must not lose
        // the rotated refresh token: the shared refresh task keeps running and still persists it.
        let refreshGate = ReplyGate()
        fixture.set([
            .init(status: 200, body: try json([
                "access_token": refreshedAccess, "refresh_token": "refresh+rotated-2",
            ]), gate: refreshGate),
        ])
        let cancelledRefresh = Task { @MainActor in try await auth.accessCredentials(forceRefresh: true) }
        // Give the refresh task a chance to start and reach the gated network call.
        try await Task.sleep(for: .milliseconds(50))
        cancelledRefresh.cancel()
        refreshGate.release()
        do {
            _ = try await cancelledRefresh.value
        } catch { }
        // Whether or not the cancelled caller observed the value, the shared refresh task must
        // have persisted the rotated refresh token.
        let afterCancelledRefresh = try await auth.accessCredentials()
        precondition(afterCancelledRefresh.accessToken == refreshedAccess, "Rotated refresh token was lost to cancellation")
        guard let storedData = try storage.load(),
              let stored = try? JSONSerialization.jsonObject(with: storedData) as? [String: Any] else {
            preconditionFailure("Could not read stored credentials after cancelled refresh")
        }
        precondition(stored["refreshToken"] as? String == "refresh+rotated-2", "\(stored)")

        storage.failDeletion(true)
        do {
            try auth.signOut()
            preconditionFailure("Accepted failed Keychain deletion")
        } catch { }
        precondition(auth.isSignedIn, "Failed deletion must retain in-memory signed-in state")
        let afterFailedDelete = try await auth.accessCredentials()
        precondition(afterFailedDelete.accountID == "acct-fixture")

        storage.failDeletion(false)
        try auth.signOut()
        precondition(!auth.isSignedIn && auth.accountLabel == nil && auth.planLabel == nil)
        do {
            _ = try await auth.accessCredentials()
            preconditionFailure("Returned credentials after sign-out")
        } catch ChatGPTSubscriptionAuth.AuthError.signedOut { }

        fixture.set([.init(status: 500, body: #"{"secret":"must-not-escape"}"#)])
        do {
            try await auth.login()
            preconditionFailure("Accepted server failure")
        } catch {
            precondition(!error.localizedDescription.contains("must-not-escape"))
        }
        precondition(!auth.isSigningIn && auth.userCode == nil)

        let gate = ReplyGate()
        fixture.set([
            .init(status: 200, body: #"{"device_auth_id":"cancel-device","user_code":"CANCEL-ME"}"#),
            .init(status: 200, body: #"{"authorization_code":"cancel-code","code_verifier":"cancel-verifier"}"#),
            .init(status: 200, body: try json([
                "access_token": access, "refresh_token": "must-not-save", "id_token": idToken,
            ]), gate: gate),
        ])
        let cancelledLogin = Task { @MainActor in try await auth.login() }
        for _ in 0..<200 {
            if fixture.recorded().count == 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fixture.recorded().count == 3, "Token exchange did not reach the fixture")
        try auth.signOut()
        gate.release()
        do {
            try await cancelledLogin.value
            preconditionFailure("Cancelled login completed")
        } catch { }
        precondition(!auth.isSignedIn && storage.isEmpty())
        print("PASS 10 subscription auth cases; no network or real credentials used")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='jtm-subscription-auth-') as temporary:
    folder = Path(temporary)
    checks = folder / 'Checks.swift'
    checks.write_text(harness)
    executable = folder / 'checks'
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / 'ModuleCache'))
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-sdk', sdk,
        '-module-cache-path', str(folder / 'ModuleCache'), '-Xfrontend', '-disable-sandbox',
        str(root / 'ios/RailMap/ChatGPTSubscriptionAuth.swift'), str(checks), '-o', str(executable),
    ], check=True, env=environment)
    subprocess.run([str(executable)], check=True)
