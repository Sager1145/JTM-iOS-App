#if DEBUG
import Darwin
import QuartzCore
import RailPresentation
import SwiftUI

/// FPS, main-thread hitches, memory footprint and CPU, one sample a second.
///
/// Runs only while the developer panel's Performance page is on screen
/// (`start`/`stop`); collapsed, nothing is scheduled at all.
@MainActor @Observable
final class DevPerfSampler {
    struct Sample: Identifiable, Equatable {
        var id: Int
        var time: Date
        var fps: Double
        var hitches: Int
        var longestFrameMs: Double
        var memoryMB: Double
        var cpuPercent: Double
    }

    static let historyLength = 120

    private(set) var samples: [Sample] = []
    private(set) var isRunning = false

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var proxy: LinkProxy?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var hitches = 0
    @ObservationIgnored private var longest: CFTimeInterval = 0
    @ObservationIgnored private var windowStart: CFTimeInterval = 0
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var nextID = 0

    func start() {
        guard link == nil else { return }
        let proxy = LinkProxy { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.step(_:)))
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.link = link
        frames = 0
        hitches = 0
        longest = 0
        windowStart = 0
        lastTimestamp = 0
        isRunning = true
    }

    func stop() {
        link?.invalidate()
        link = nil
        proxy = nil
        isRunning = false
    }

    func clear() { samples = [] }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if windowStart == 0 {
            windowStart = now
            lastTimestamp = now
            return
        }
        let frame = now - lastTimestamp
        lastTimestamp = now
        frames += 1
        longest = max(longest, frame)
        // A hitch: a frame that took over 1.5 of the display's own interval.
        let expected = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        if frame > expected * 1.5 + 0.001 { hitches += 1 }
        guard now - windowStart >= 1 else { return }
        let elapsed = now - windowStart
        let memory = Self.footprintMB()
        let sample = Sample(
            id: nextID, time: Date(), fps: Double(frames) / elapsed, hitches: hitches,
            longestFrameMs: longest * 1000, memoryMB: memory, cpuPercent: Self.cpuPercent())
        nextID += 1
        samples.append(sample)
        if samples.count > Self.historyLength { samples.removeFirst(samples.count - Self.historyLength) }
        frames = 0
        hitches = 0
        longest = 0
        windowStart = now
    }

    var json: AppControlJSON {
        .array(samples.map { sample in
            [
                "at": .string(sample.time.formatted(.iso8601)), "fps": .number((sample.fps * 10).rounded() / 10),
                "hitches": .number(Double(sample.hitches)),
                "longestFrameMs": .number((sample.longestFrameMs * 10).rounded() / 10),
                "memoryMB": .number((sample.memoryMB * 10).rounded() / 10),
                "cpuPercent": .number((sample.cpuPercent * 10).rounded() / 10),
            ]
        })
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Sum of every thread's CPU usage, as a percentage of one core.
    static func cpuPercent() -> Double {
        var threads: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0
        for index in 0..<Int(count) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            guard status == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 else { continue }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
        }
        for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, threads[index]) }
        return total
    }
}

/// CADisplayLink retains its target; this breaks the cycle.
@MainActor
private final class LinkProxy: NSObject {
    let handler: @MainActor (CADisplayLink) -> Void
    init(_ handler: @escaping @MainActor (CADisplayLink) -> Void) { self.handler = handler }
    @objc func step(_ link: CADisplayLink) { handler(link) }
}
#endif
