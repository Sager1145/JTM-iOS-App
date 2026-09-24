import Foundation

/// Transport-independent wire helpers for ChatGPT's Codex subscription endpoints.
public enum ChatGPTSubscriptionProtocol {
    public struct Model: Identifiable, Sendable, Equatable, Codable {
        public let slug: String
        public let displayName: String

        public var id: String { slug }

        public init(slug: String, displayName: String) {
            self.slug = slug
            self.displayName = displayName
        }

        private enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
        }
    }

    public enum Error: Swift.Error, Sendable, Equatable, LocalizedError {
        case invalidPrompt
        case invalidModel
        case malformedModelCatalog(String)
        case requestEncodingFailed(String)
        case malformedStreamEvent(String)
        case responseFailed(String)
        case responseIncomplete
        case emptyResponse
        case truncatedStream
        case eventAfterCompletion

        public var errorDescription: String? {
            switch self {
            case .invalidPrompt:
                "The research prompt is empty."
            case .invalidModel:
                "The selected ChatGPT model is empty."
            case .malformedModelCatalog(let reason):
                "The ChatGPT model catalog is invalid: \(reason)"
            case .requestEncodingFailed(let reason):
                "The ChatGPT request could not be encoded: \(reason)"
            case .malformedStreamEvent(let reason):
                "The ChatGPT response stream is invalid: \(reason)"
            case .responseFailed(let reason):
                "ChatGPT could not complete the response: \(reason)"
            case .responseIncomplete:
                "ChatGPT ended the response before it was complete."
            case .emptyResponse:
                "ChatGPT completed the response without returning text."
            case .truncatedStream:
                "The ChatGPT response stream ended before a completed response arrived."
            case .eventAfterCompletion:
                "The ChatGPT response stream contained data after its completed response."
            }
        }
    }

    /// Decodes picker-visible models in catalog order, keeping the first visible occurrence of
    /// each slug. Subscription catalogs can legitimately advertise models unavailable to API-key
    /// clients, so `supported_in_api` is deliberately not part of this projection.
    public static func models(from data: Data) throws -> [Model] {
        let catalog: Catalog
        do {
            catalog = try JSONDecoder().decode(Catalog.self, from: data)
        } catch {
            throw Error.malformedModelCatalog(error.localizedDescription)
        }

        var seen: Set<String> = []
        var result: [Model] = []
        for entry in catalog.models where entry.isPickerVisible {
            let slug = entry.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            guard slug.isEmpty == false, seen.insert(slug).inserted else { continue }
            let name = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(Model(slug: slug, displayName: name.isEmpty ? slug : name))
        }
        return result
    }

    /// Encodes a private, streaming Responses request for a journey-fact research turn.
    public static func requestBody(prompt: String, model: String) throws -> Data {
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw Error.invalidPrompt
        }
        guard model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw Error.invalidModel
        }

        let request = Request(
            model: model,
            instructions: "Research the supplied railway journey facts using web search and authoritative sources. Do not guess. Return JSON only.",
            input: [
                .init(role: "user", content: [.init(type: "input_text", text: prompt)])
            ],
            tools: [.init(type: "web_search", externalWebAccess: true)],
            store: false,
            stream: true)

        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw Error.requestEncodingFailed(error.localizedDescription)
        }
    }

    /// Classifies a non-2xx HTTP response body from ChatGPT's Codex subscription endpoints.
    public struct ServiceFailure: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case usageLimitReached
            case usageNotIncluded
            case rateLimited
            case unauthorized
            case forbidden
            case other
        }

        public let status: Int
        public let kind: Kind
        public let message: String?
        public let resetsAt: Date?
    }

    /// Parses a non-2xx response body to classify the failure. Undecodable bodies still produce a
    /// status-based classification with a `nil` message.
    public static func serviceFailure(status: Int, body: Data, now: Date = Date()) -> ServiceFailure {
        var type: String?
        var code: String?
        var message: String?
        var resetsAt: Date?

        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                type = error["type"] as? String
                code = error["code"] as? String
                message = error["message"] as? String
                if let resetsAtSeconds = Self.number(error["resets_at"]) {
                    resetsAt = Date(timeIntervalSince1970: resetsAtSeconds)
                } else if let resetsInSeconds = Self.number(error["resets_in_seconds"]) {
                    resetsAt = now.addingTimeInterval(resetsInSeconds)
                }
            } else if let errorCode = json["error"] as? String {
                code = errorCode
                message = json["error_description"] as? String
            } else if let detail = json["detail"] as? String {
                message = detail
            } else if let detail = json["detail"] as? [String: Any] {
                code = detail["code"] as? String
                message = detail["message"] as? String
            } else if let plainMessage = json["message"] as? String {
                message = plainMessage
            }
        }

        let knownCodes: Set<String> = ["usage_limit_reached", "usage_not_included", "rate_limit_exceeded"]
        let knownCode = [type, code].compactMap { $0?.lowercased() }.first { knownCodes.contains($0) }

        let kind: ServiceFailure.Kind
        switch knownCode {
        case "usage_limit_reached":
            kind = .usageLimitReached
        case "usage_not_included":
            kind = .usageNotIncluded
        case "rate_limit_exceeded":
            kind = .rateLimited
        default:
            switch status {
            case 429: kind = .rateLimited
            case 401: kind = .unauthorized
            case 403: kind = .forbidden
            default: kind = .other
            }
        }

        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cappedMessage: String?
        if let trimmedMessage, trimmedMessage.isEmpty == false {
            cappedMessage = String(trimmedMessage.prefix(300))
        } else {
            cappedMessage = nil
        }

        return ServiceFailure(status: status, kind: kind, message: cappedMessage, resetsAt: resetsAt)
    }

    private static func number(_ value: Any?) -> TimeInterval? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }

    /// Incrementally frames Server-Sent Events and commits text only when the server sends a
    /// successful `response.completed` event.
    public struct ResponseStream: Sendable {
        private var dataLines: [String] = []
        private var keyOrder: [String] = []
        private var deltaTextByKey: [String: String] = [:]
        private var finalItemTextByKey: [String: String] = [:]
        private var finalItemPhaseByKey: [String: String] = [:]
        private var didComplete = false

        public init() {}

        /// Consumes one logical SSE line. Callers must preserve empty lines because they delimit
        /// events. CRLF input is accepted by stripping the trailing carriage return.
        public mutating func consume(line originalLine: String) throws -> String? {
            var line = originalLine
            if line.last == "\r" {
                line.removeLast()
            }

            if line.isEmpty {
                guard dataLines.isEmpty == false else { return nil }
                let payload = dataLines.joined(separator: "\n")
                dataLines.removeAll(keepingCapacity: true)
                return try consumeEvent(payload)
            }

            if line.hasPrefix(":") {
                return nil
            }

            let field: Substring
            let value: Substring
            if let colon = line.firstIndex(of: ":") {
                field = line[..<colon]
                let valueStart = line.index(after: colon)
                value = line[valueStart...]
            } else {
                field = Substring(line)
                value = ""
            }

            guard field == "data" else { return nil }
            let normalized = value.first == " " ? value.dropFirst() : value[...]
            dataLines.append(String(normalized))
            return nil
        }

        /// Verifies that the server closed the stream only after a blank-delimited completed
        /// event. Buffered event data at EOF is a truncated SSE event and is never committed.
        public mutating func finish() throws {
            guard dataLines.isEmpty else { throw Error.truncatedStream }
            guard didComplete else { throw Error.truncatedStream }
        }

        private mutating func consumeEvent(_ payload: String) throws -> String? {
            if payload == "[DONE]" {
                return nil
            }
            guard didComplete == false else {
                throw Error.eventAfterCompletion
            }
            guard let data = payload.data(using: .utf8) else {
                throw Error.malformedStreamEvent("event data is not UTF-8")
            }

            let value: Any
            do {
                value = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw Error.malformedStreamEvent(error.localizedDescription)
            }
            guard let event = value as? [String: Any], let type = event["type"] as? String else {
                throw Error.malformedStreamEvent("event is missing its type")
            }

            switch type {
            case "response.output_text.delta":
                guard let delta = event["delta"] as? String else {
                    throw Error.malformedStreamEvent("output-text delta is missing its text")
                }
                let key = Self.deltaKey(from: event)
                if keyOrder.contains(key) == false {
                    keyOrder.append(key)
                }
                deltaTextByKey[key, default: ""] += delta
                return nil

            case "response.output_item.done":
                if let item = event["item"] as? [String: Any] {
                    recordFinalItem(item, outputIndex: event["output_index"] as? Int)
                }
                return nil

            case "response.completed":
                guard let response = event["response"] as? [String: Any] else {
                    throw Error.malformedStreamEvent("completed event is missing its response")
                }
                guard response["status"] as? String == "completed" else {
                    throw Error.responseIncomplete
                }

                let outputText = Self.outputText(from: response)
                let finalText = outputText.isEmpty ? deltaFallbackText() : outputText
                guard finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw Error.emptyResponse
                }
                didComplete = true
                return finalText

            case "response.failed", "error":
                throw Error.responseFailed(Self.failureMessage(from: event) ?? "the server reported an error")

            case "response.incomplete":
                throw Error.responseIncomplete

            default:
                return nil
            }
        }

        private mutating func recordFinalItem(_ item: [String: Any], outputIndex: Int?) {
            let type = item["type"] as? String
            guard type == "message" || (type == nil && item["content"] != nil) else { return }
            let key = (item["id"] as? String) ?? outputIndex.map { String($0) } ?? ""
            if keyOrder.contains(key) == false {
                keyOrder.append(key)
            }
            finalItemTextByKey[key] = Self.joinedOutputText(from: item)
            if let phase = item["phase"] as? String {
                finalItemPhaseByKey[key] = phase
            }
        }

        private func deltaFallbackText() -> String {
            var finalAnswerText: String?
            var lastNonEmptyText: String?
            for key in keyOrder {
                let text = finalItemTextByKey[key] ?? deltaTextByKey[key] ?? ""
                guard text.isEmpty == false else { continue }
                lastNonEmptyText = text
                if finalItemPhaseByKey[key] == "final_answer" {
                    finalAnswerText = text
                }
            }
            return finalAnswerText ?? lastNonEmptyText ?? ""
        }

        private static func deltaKey(from event: [String: Any]) -> String {
            if let itemID = event["item_id"] as? String {
                return itemID
            }
            if let outputIndex = event["output_index"] as? Int {
                return String(outputIndex)
            }
            return ""
        }

        private static func joinedOutputText(from item: [String: Any]) -> String {
            guard let content = item["content"] as? [[String: Any]] else { return "" }
            var text = ""
            for part in content where part["type"] as? String == "output_text" {
                if let partText = part["text"] as? String {
                    text += partText
                }
            }
            return text
        }

        private static func outputText(from response: [String: Any]) -> String {
            if let output = response["output"] as? [[String: Any]] {
                var finalAnswerText: String?
                var lastNonEmptyText: String?
                for item in output {
                    let type = item["type"] as? String
                    guard type == "message" || (type == nil && item["content"] != nil) else { continue }
                    let text = joinedOutputText(from: item)
                    guard text.isEmpty == false else { continue }
                    lastNonEmptyText = text
                    if item["phase"] as? String == "final_answer" {
                        finalAnswerText = text
                    }
                }
                if let text = finalAnswerText ?? lastNonEmptyText {
                    return text
                }
            }
            if let text = response["output_text"] as? String {
                return text
            }
            return ""
        }

        private static func failureMessage(from event: [String: Any]) -> String? {
            if let message = event["message"] as? String, message.isEmpty == false {
                return message
            }
            for containerName in ["error", "response"] {
                if let container = event[containerName] as? [String: Any],
                   let message = container["message"] as? String,
                   message.isEmpty == false
                {
                    return message
                }
                if let container = event[containerName] as? [String: Any],
                   let error = container["error"] as? [String: Any],
                   let message = error["message"] as? String,
                   message.isEmpty == false
                {
                    return message
                }
            }
            return nil
        }
    }
}

private extension ChatGPTSubscriptionProtocol {
    struct Catalog: Decodable {
        let models: [CatalogModel]
    }

    struct CatalogModel: Decodable {
        let slug: String
        let displayName: String
        let visibility: String?

        var isPickerVisible: Bool {
            switch visibility?.lowercased() {
            case nil, "list", "show", "visible": true
            case "hide", "hidden", "none": false
            default: false
            }
        }

        private enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
            case visibility
        }
    }

    struct Request: Encodable {
        struct Input: Encodable {
            struct Content: Encodable {
                let type: String
                let text: String
            }

            let role: String
            let content: [Content]
        }

        struct Tool: Encodable {
            let type: String
            let externalWebAccess: Bool?

            private enum CodingKeys: String, CodingKey {
                case type
                case externalWebAccess = "external_web_access"
            }
        }

        let model: String
        let instructions: String
        let input: [Input]
        let tools: [Tool]
        let store: Bool
        let stream: Bool
    }
}
