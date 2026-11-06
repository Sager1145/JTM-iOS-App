import Foundation
import Testing

@testable import RailCore

struct ChatGPTSubscriptionProtocolTests {
    @Test("model catalog keeps visible subscription models and stably deduplicates slugs")
    func modelCatalogVisibilityAndDeduplication() throws {
        let data = Data(#"""
        {
          "models": [
            {"slug":"gpt-visible","display_name":"Visible","visibility":"list","supported_in_api":false},
            {"slug":"gpt-hidden","display_name":"Hidden","visibility":"hide","supported_in_api":true},
            {"slug":"gpt-visible","display_name":"Duplicate","visibility":"list","supported_in_api":true},
            {"slug":"gpt-shown","display_name":"Shown","visibility":"show","supported_in_api":false},
            {"slug":"gpt-none","display_name":"None","visibility":"none","supported_in_api":true}
          ]
        }
        """#.utf8)

        let models = try ChatGPTSubscriptionProtocol.models(from: data)

        #expect(models == [
            .init(slug: "gpt-visible", displayName: "Visible"),
            .init(slug: "gpt-shown", displayName: "Shown"),
        ])
        #expect(models.map(\.id) == ["gpt-visible", "gpt-shown"])
    }

    @Test("request is private and limits the turn to user text plus web search")
    func requestBodyPrivacyAndShape() throws {
        let data = try ChatGPTSubscriptionProtocol.requestBody(
            prompt: "Complete these journey facts",
            model: "gpt-subscription")
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["model"] as? String == "gpt-subscription")
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        let instructions = try #require(body["instructions"] as? String)
        #expect(instructions.contains("web search"))
        #expect(instructions.contains("Do not guess"))
        #expect(instructions.contains("JSON only"))

        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input.first?["role"] as? String == "user")
        let content = try #require(input.first?["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content.first?["type"] as? String == "input_text")
        #expect(content.first?["text"] as? String == "Complete these journey facts")

        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "web_search")
        #expect(tools.first?["external_web_access"] as? Bool == true)
    }

    @Test("stream returns nothing before completion and prefers canonical output over deltas")
    func completedOutputIsTheOnlyCommit() throws {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()

        #expect(try stream.consume(line: ": keepalive\r") == nil)
        #expect(try stream.consume(line: #"data: {"type":"response.output_text.delta","delta":"partial "}"#) == nil)
        #expect(try stream.consume(line: "\r") == nil)
        #expect(try stream.consume(line: #"data: {"type":"response.output_text.delta","delta":"draft"}"#) == nil)
        #expect(try stream.consume(line: "") == nil)

        let completed = #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"web_search_call","status":"completed"},{"type":"message","content":[{"type":"output_text","text":"{\"trains\":[]}"}]}]}}"#
        #expect(try stream.consume(line: "data: \(completed)") == nil)
        #expect(try stream.consume(line: "") == #"{"trains":[]}"#)
        #expect(try stream.consume(line: "data: [DONE]") == nil)
        #expect(try stream.consume(line: "") == nil)
        try stream.finish()
    }

    @Test("multiline SSE data is joined before JSON decoding")
    func multilineDataEvent() throws {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()

        #expect(try stream.consume(line: "event: response.completed") == nil)
        #expect(try stream.consume(line: "data: {") == nil)
        #expect(try stream.consume(line: #"data: "type":"response.completed","#) == nil)
        #expect(try stream.consume(line: #"data: "response":{"status":"completed","output_text":"ready"}}"#) == nil)
        #expect(try stream.consume(line: "") == "ready")
        try stream.finish()
    }

    @Test("completed event may commit accumulated deltas when output is omitted")
    func completedEventFallsBackToDeltas() throws {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()
        try consumeEvent(#"{"type":"response.output_text.delta","delta":"one"}"#, with: &stream)
        try consumeEvent(#"{"type":"response.output_text.delta","delta":" two"}"#, with: &stream)

        #expect(try stream.consume(line: #"data: {"type":"response.completed","response":{"status":"completed","output":[]}}"#) == nil)
        #expect(try stream.consume(line: "") == "one two")
        try stream.finish()
    }

    @Test("failed and incomplete terminal events are rejected", arguments: [
        #"{"type":"response.failed","response":{"error":{"message":"research failed"}}}"#,
        #"{"type":"response.incomplete","response":{"status":"incomplete"}}"#,
        #"{"type":"error","message":"stream failed"}"#,
        #"{"type":"response.completed","response":{"status":"incomplete","output_text":"draft"}}"#,
    ])
    func rejectedTerminalEvents(event: String) {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()
        do {
            _ = try stream.consume(line: "data: \(event)")
            _ = try stream.consume(line: "")
            Issue.record("Expected terminal event to be rejected")
        } catch ChatGPTSubscriptionProtocol.Error.responseFailed {
            // Expected for explicit failure events.
        } catch ChatGPTSubscriptionProtocol.Error.responseIncomplete {
            // Expected for incomplete responses.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("EOF before a blank-delimited completed event is truncated")
    func truncatedStreamIsRejected() {
        var missingCompletion = ChatGPTSubscriptionProtocol.ResponseStream()
        #expect(throws: ChatGPTSubscriptionProtocol.Error.truncatedStream) {
            try missingCompletion.finish()
        }

        var partialEvent = ChatGPTSubscriptionProtocol.ResponseStream()
        do {
            _ = try partialEvent.consume(line: #"data: {"type":"response.completed""#)
        } catch {
            Issue.record("A buffered data line should not be decoded before its delimiter: \(error)")
        }
        #expect(throws: ChatGPTSubscriptionProtocol.Error.truncatedStream) {
            try partialEvent.finish()
        }
    }

    @Test("a preamble message before the final message is ignored")
    func preambleMessageIsIgnored() throws {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()
        let completed = #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Let me check that."}]},{"type":"message","content":[{"type":"output_text","text":"{\"trains\":[]}"}]}]}}"#
        #expect(try stream.consume(line: "data: \(completed)") == nil)
        #expect(try stream.consume(line: "") == #"{"trains":[]}"#)
        try stream.finish()
    }

    @Test("a message with phase final_answer wins over a later commentary message")
    func finalAnswerPhaseIsPreferred() throws {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()
        let completed = #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","phase":"final_answer","content":[{"type":"output_text","text":"{\"trains\":[]}"}]},{"type":"message","content":[{"type":"output_text","text":"by the way, commentary"}]}]}}"#
        #expect(try stream.consume(line: "data: \(completed)") == nil)
        #expect(try stream.consume(line: "") == #"{"trains":[]}"#)
        try stream.finish()
    }

    @Test("a delta-only stream keyed by item id commits only the last item's text")
    func deltaFallbackUsesLastItem() throws {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()
        try consumeEvent(#"{"type":"response.output_text.delta","item_id":"item_1","delta":"preamble text"}"#, with: &stream)
        try consumeEvent(#"{"type":"response.output_text.delta","item_id":"item_2","delta":"{\"trains\":[]}"}"#, with: &stream)

        #expect(try stream.consume(line: #"data: {"type":"response.completed","response":{"status":"completed","output":[]}}"#) == nil)
        #expect(try stream.consume(line: "") == #"{"trains":[]}"#)
        try stream.finish()
    }

    @Test("output_item.done supplies the final text when completed.output is empty")
    func outputItemDoneSuppliesFinalText() throws {
        var stream = ChatGPTSubscriptionProtocol.ResponseStream()
        let done = #"{"type":"response.output_item.done","item":{"id":"item_1","type":"message","phase":"final_answer","content":[{"type":"output_text","text":"{\"trains\":[]}"}]}}"#
        #expect(try stream.consume(line: "data: \(done)") == nil)
        #expect(try stream.consume(line: "") == nil)

        #expect(try stream.consume(line: #"data: {"type":"response.completed","response":{"status":"completed","output":[]}}"#) == nil)
        #expect(try stream.consume(line: "") == #"{"trains":[]}"#)
        try stream.finish()
    }

    @Test("service failure classifies a rate-limited usage response with resets_at")
    func serviceFailureUsageLimitReachedWithResetsAt() {
        let body = Data(#"{"error":{"type":"usage_limit_reached","message":"You've hit your usage limit.","resets_at":1700000000}}"#.utf8)
        let failure = ChatGPTSubscriptionProtocol.serviceFailure(status: 429, body: body)
        #expect(failure.status == 429)
        #expect(failure.kind == .usageLimitReached)
        #expect(failure.message == "You've hit your usage limit.")
        #expect(failure.resetsAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("service failure classifies a usage-limit code delivered as a 404")
    func serviceFailureUsageLimitReachedAs404() {
        let body = Data(#"{"error":{"code":"usage_limit_reached","message":"limit reached"}}"#.utf8)
        let failure = ChatGPTSubscriptionProtocol.serviceFailure(status: 404, body: body)
        #expect(failure.status == 404)
        #expect(failure.kind == .usageLimitReached)
    }

    @Test("service failure classifies a usage-limit code when type is unrelated")
    func serviceFailureUsageLimitReachedByCodeDespiteUnrelatedType() {
        let body = Data(#"{"error":{"type":"invalid_request_error","code":"usage_limit_reached"}}"#.utf8)
        let failure = ChatGPTSubscriptionProtocol.serviceFailure(status: 400, body: body)
        #expect(failure.kind == .usageLimitReached)
    }

    @Test("service failure classifies usage_not_included")
    func serviceFailureUsageNotIncluded() {
        let body = Data(#"{"error":{"type":"usage_not_included","message":"Not on your plan."}}"#.utf8)
        let failure = ChatGPTSubscriptionProtocol.serviceFailure(status: 403, body: body)
        #expect(failure.kind == .usageNotIncluded)
        #expect(failure.message == "Not on your plan.")
    }

    @Test("service failure reads a detail string")
    func serviceFailureDetailString() {
        let body = Data(#"{"detail":"bad request"}"#.utf8)
        let failure = ChatGPTSubscriptionProtocol.serviceFailure(status: 400, body: body)
        #expect(failure.kind == .other)
        #expect(failure.message == "bad request")
    }

    @Test("service failure falls back to status-based classification for garbage bodies")
    func serviceFailureGarbageBody() {
        let body = Data("not json".utf8)
        let failure = ChatGPTSubscriptionProtocol.serviceFailure(status: 500, body: body)
        #expect(failure.status == 500)
        #expect(failure.kind == .other)
        #expect(failure.message == nil)
        #expect(failure.resetsAt == nil)
    }

    private func consumeEvent(
        _ event: String,
        with stream: inout ChatGPTSubscriptionProtocol.ResponseStream
    ) throws {
        _ = try stream.consume(line: "data: \(event)")
        _ = try stream.consume(line: "")
    }
}
