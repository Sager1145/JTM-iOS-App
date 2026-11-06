#if DEBUG
import Foundation
import Testing
import RailCore

struct SignpostRecorderTests {
    @Test("Inactive, begin records nothing and costs no token")
    func inactiveIsFree() {
        let recorder = SignpostRecorder(active: false)
        #expect(recorder.begin("map.rebuild") == nil)
        recorder.end(nil)
        #expect(recorder.recent().isEmpty)
        #expect(recorder.aggregates().isEmpty)
    }

    @Test("Active, intervals aggregate by name, newest first")
    func aggregates() {
        let recorder = SignpostRecorder(active: true)
        recorder.end(recorder.begin("map.rebuild"))
        recorder.record(name: "map.rebuild", milliseconds: 12)
        recorder.record(name: "route.cacheRead", milliseconds: 3)
        let rebuild = recorder.aggregate(named: "map.rebuild")
        #expect(rebuild?.count == 2)
        #expect(rebuild?.maxMs == 12)
        #expect(recorder.aggregates().first?.name == "map.rebuild")
        #expect(recorder.recent(1).first?.name == "route.cacheRead")
    }

    @Test("The ring buffer keeps only the newest entries")
    func ringBuffer() {
        let recorder = SignpostRecorder(active: true, capacity: 3)
        for index in 0..<5 { recorder.record(name: "n\(index)", milliseconds: Double(index)) }
        #expect(recorder.recent(10).map(\.name) == ["n4", "n3", "n2"])
        #expect(recorder.aggregates().count == 5)
        recorder.reset()
        #expect(recorder.recent().isEmpty)
    }
}
#endif
