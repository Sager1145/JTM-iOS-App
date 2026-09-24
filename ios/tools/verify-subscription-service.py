#!/usr/bin/env python3
"""Exercise production subscription HTTP code with URLProtocol fixtures (no network)."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
if len(sys.argv) != 2:
    raise SystemExit('Usage: verify-subscription-service.py SWIFT_BUILD_SCRATCH')
scratch = Path(sys.argv[1]).resolve()
library = next(scratch.rglob('libRailCore.a'), None)
modules = library.parent if library else next(scratch.glob('*/debug/Modules'), None)
if modules is None:
    raise SystemExit('Build RailKit in the supplied scratch directory first.')
objects = [library] if library else sorted((modules.parent / 'RailCore.build').glob('*.swift.o'))
harness = r'''
import Foundation
import RailCore

@MainActor final class ChatGPTSubscriptionAuth {
    var refreshes = 0
    func accessCredentials(forceRefresh: Bool = false) async throws -> (accessToken: String, accountID: String) {
        if forceRefresh { refreshes += 1 }
        return (forceRefresh ? "fixture-refreshed" : "fixture-access", "fixture-account")
    }
}

final class Fixtures: @unchecked Sendable {
    struct Reply: Sendable { let status: Int; let body: String }
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
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": request.url!.path.hasSuffix("responses") ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main struct Checks {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        let auth = ChatGPTSubscriptionAuth()
        let service = ChatGPTSubscriptionService(auth: auth, session: session)
        let fixture = FixtureProtocol.fixtures
        let catalog = #"{"models":[{"slug":"fixture-model","display_name":"Fixture Model","visibility":"list"}]}"#
        fixture.set([.init(status: 401, body: ""), .init(status: 200, body: catalog)])
        let models = try await service.models()
        precondition(models.map(\.id) == ["fixture-model"])
        precondition(auth.refreshes == 1)
        let requests = fixture.recorded()
        precondition(requests.count == 2)
        precondition(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-refreshed")
        precondition(requests[1].value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fixture-account")
        precondition(requests[0].url?.host == "chatgpt.com")

        let completed = #"data: {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"trains\":[]}"}]}]}}"# + "\n\n"
        fixture.set([.init(status: 200, body: completed)])
        let text = try await service.complete(prompt: "fixture prompt", model: "fixture-model")
        precondition(text == #"{"trains":[]}"#)
        precondition(fixture.recorded().first?.httpMethod == "POST")

        fixture.set([.init(status: 200, body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n")])
        do { _ = try await service.complete(prompt: "fixture", model: "fixture-model"); preconditionFailure("Accepted truncated stream") }
        catch { }

        fixture.set([.init(status: 429, body: "private server response")])
        do { _ = try await service.models(); preconditionFailure("Accepted rate limit") }
        catch ChatGPTSubscriptionService.Failure.rateLimited(let message) {
            precondition(message.contains("rate-limiting requests"), message)
        }
        precondition(auth.refreshes == 1, "Rate limit must not refresh credentials")
        precondition(fixture.recorded().count == 1)

        fixture.set([.init(status: 401, body: ""), .init(status: 401, body: "")])
        do { _ = try await service.models(); preconditionFailure("Accepted invalid credentials") }
        catch ChatGPTSubscriptionService.Failure.signInRequired { }
        precondition(fixture.recorded().count == 2, "401 retries must be bounded")

        // A plain 403 (no usage_not_included code) must not claim the subscription is
        // unavailable; it should surface as a generic http failure.
        fixture.set([.init(status: 403, body: "")])
        do { _ = try await service.models(); preconditionFailure("Accepted denied model") }
        catch ChatGPTSubscriptionService.Failure.http(let status, _) {
            precondition(status == 403, "\(status)")
        }

        fixture.set([.init(status: 403, body: #"{"error":{"code":"usage_not_included"}}"#)])
        do { _ = try await service.models(); preconditionFailure("Accepted usage_not_included") }
        catch ChatGPTSubscriptionService.Failure.subscriptionUnavailable { }

        // A usage-limit body with a reset time must surface a rate-limited failure whose
        // message names the reset time, even though the server responded with plain 429.
        fixture.set([.init(status: 429, body: #"{"error":{"code":"usage_limit_reached","resets_in_seconds":120}}"#)])
        do {
            _ = try await service.models()
            preconditionFailure("Accepted usage limit")
        } catch ChatGPTSubscriptionService.Failure.rateLimited(let message) {
            precondition(message.contains("Try again after"), message)
            precondition(!message.contains("it resets"), message)
        }

        // The server sometimes reports usage_limit_reached on HTTP 404; it must still classify
        // as rateLimited rather than falling through to a generic http(404) failure.
        fixture.set([.init(status: 404, body: #"{"error":{"code":"usage_limit_reached"}}"#)])
        do {
            _ = try await service.models()
            preconditionFailure("Accepted usage limit reported as 404")
        } catch ChatGPTSubscriptionService.Failure.rateLimited { }

        // Other HTTP failures should surface the server's message when present.
        fixture.set([.init(status: 400, body: #"{"detail":"bad"}"#)])
        do {
            _ = try await service.models()
            preconditionFailure("Accepted malformed request")
        } catch ChatGPTSubscriptionService.Failure.http(let status, let message) {
            precondition(status == 400, "\(status)")
            precondition(message == "bad", "\(String(describing: message))")
            precondition(
                ChatGPTSubscriptionService.Failure.http(status, message).errorDescription?.contains("bad") == true
            )
        }

        print("PASS 9 production subscription HTTP cases; no network or credentials used")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-subscription-service-') as temporary:
    folder = Path(temporary)
    checks = folder / 'Checks.swift'
    checks.write_text(harness)
    executable = folder / 'checks'
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / 'ModuleCache'))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-sdk', sdk,
        '-I', str(modules), str(root / 'ios/RailMap/ChatGPTSubscriptionService.swift'),
        str(checks), *map(str, objects), '-o', str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True)
