import Foundation
import RailCore

/// Direct subscription requests; there is no application server or API key.
@MainActor
final class ChatGPTSubscriptionService {
    private let auth: ChatGPTSubscriptionAuth
    private let session: URLSession
    private static let base = "https://chatgpt.com/backend-api/codex"

    init(auth: ChatGPTSubscriptionAuth, session: URLSession? = nil) {
        self.auth = auth
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: configuration, delegate: SubscriptionRedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func models() async throws -> [ChatGPTSubscriptionProtocol.Model] {
        var version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            .split(separator: ".").compactMap { Int($0) }.map(String.init)
        while version.count < 3 { version.append("0") }
        let clientVersion = version.prefix(3).joined(separator: ".")
        for attempt in 0...1 {
            let request = try await request(path: "/models?client_version=" + clientVersion, refresh: attempt == 1)
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            if http.statusCode == 401, attempt == 0 { continue }
            try validate(http.statusCode, body: data)
            return try ChatGPTSubscriptionProtocol.models(from: data)
        }
        throw Failure.signInRequired
    }

    func complete(prompt: String, model: String) async throws -> String {
        let body = try ChatGPTSubscriptionProtocol.requestBody(prompt: prompt, model: model)
        for attempt in 0...1 {
            var request = try await request(path: "/responses", refresh: attempt == 1)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            if http.statusCode == 401, attempt == 0 { continue }
            if !(200..<300).contains(http.statusCode) {
                let errorBody = try await readBoundedBody(bytes)
                try validate(http.statusCode, body: errorBody)
            }
            var parser = ChatGPTSubscriptionProtocol.ResponseStream()
            // AsyncBytes.lines omits empty lines, which are SSE event boundaries.
            var line = Data()
            var received = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                received += 1
                guard received <= 8 * 1_024 * 1_024 else { throw Failure.invalidResponse }
                if byte == 10 {
                    guard let text = String(data: line, encoding: .utf8) else { throw Failure.invalidResponse }
                    line.removeAll(keepingCapacity: true)
                    if let result = try parser.consume(line: text) { return result }
                } else {
                    line.append(byte)
                }
            }
            guard line.isEmpty else { throw Failure.invalidResponse }
            try parser.finish()
            throw Failure.invalidResponse
        }
        throw Failure.signInRequired
    }

    private func request(path: String, refresh: Bool) async throws -> URLRequest {
        let credentials = try await auth.accessCredentials(forceRefresh: refresh)
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: Self.base + path)!)
        request.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("JTM-iOS", forHTTPHeaderField: "originator")
        request.setValue("JTM-iOS/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Reads a bounded prefix of a streamed response body so an error body can still be
    /// classified without buffering an unbounded response.
    private func readBoundedBody(_ bytes: URLSession.AsyncBytes, limit: Int = 64 * 1_024) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }

    private func validate(_ status: Int, body: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let failure = ChatGPTSubscriptionProtocol.serviceFailure(status: status, body: body)
        switch failure.kind {
        case .usageLimitReached:
            throw Failure.rateLimited(message: Self.usageLimitMessage(resetsAt: failure.resetsAt))
        case .rateLimited:
            throw Failure.rateLimited(message: Self.rateLimitedMessage(serverMessage: failure.message))
        case .usageNotIncluded:
            throw Failure.subscriptionUnavailable
        case .forbidden:
            throw Failure.http(status, failure.message)
        case .unauthorized:
            throw Failure.signInRequired
        case .other:
            throw Failure.http(status, failure.message)
        }
    }

    private static func usageLimitMessage(resetsAt: Date?) -> String {
        guard let resetsAt else {
            return "The subscription usage limit was reached. Try again after it resets."
        }
        let when = resetsAt.formatted(date: .abbreviated, time: .shortened)
        return "The subscription usage limit was reached. Try again after \(when)."
    }

    private static func rateLimitedMessage(serverMessage: String?) -> String {
        let base = "ChatGPT is rate-limiting requests. Wait a moment and try again."
        guard let serverMessage, serverMessage.isEmpty == false else { return base }
        return "\(base) (\(serverMessage))"
    }

    enum Failure: LocalizedError {
        case invalidResponse
        case signInRequired
        case subscriptionUnavailable
        case rateLimited(message: String)
        case http(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The subscription service returned an incomplete response."
            case .signInRequired: "Your ChatGPT session has expired. Sign in again."
            case .subscriptionUnavailable: "This account cannot access the requested subscription model or tool."
            case .rateLimited(let message): message
            case .http(let status, let message):
                if let message {
                    "The subscription service returned HTTP \(status): \(message)"
                } else {
                    "The subscription service returned HTTP \(status)."
                }
            }
        }
    }
}

private final class SubscriptionRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
