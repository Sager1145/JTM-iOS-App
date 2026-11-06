#if DEBUG
import Charts
import RailCore
import RailPresentation
import SwiftUI

/// The ball, or the expanded panel. Hosted by `DevToolsController`'s window.
struct DevToolsRootView: View {
    let controller: DevToolsController

    var body: some View {
        Group {
            if controller.isExpanded {
                DevToolsPanel(controller: controller)
                    .transition(.opacity)
            } else {
                DevToolsBall(controller: controller)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct DevToolsBall: View {
    let controller: DevToolsController

    var body: some View {
        Button { controller.setExpanded(true) } label: {
            ZStack {
                Circle().fill(.black.opacity(0.72))
                Circle().strokeBorder(DevStorage.isReal ? Color.red : Color.green, lineWidth: 3)
                Image(systemName: "ladybug.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: DevToolsController.ballSize, height: DevToolsController.ballSize)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("devToolsBall")
        .accessibilityLabel(DevStorage.isReal ? "Developer tools, real store" : "Developer tools, isolated store")
    }
}

private struct DevToolsPanel: View {
    @Bindable var controller: DevToolsController

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "ladybug.fill")
                Text("Developer").font(.headline)
                Spacer()
                Button { controller.setExpanded(false) } label: {
                    Image(systemName: "chevron.down.circle.fill").font(.title2)
                }
                .accessibilityIdentifier("devToolsCollapse")
            }
            StorageBanner()
            Picker("Page", selection: $controller.page) {
                ForEach(DevToolsController.Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Group {
                switch controller.page {
                case .performance: PerformancePage(sampler: controller.sampler)
                case .triggers: TriggersPage(controller: controller)
                case .state: StatePage()
                case .tools: ToolsPage(controller: controller)
                case .logs: LogsPage()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .font(.caption)
    }
}

/// Always visible in the panel; red whenever the real ride store is in use.
private struct StorageBanner: View {
    var body: some View {
        let real = DevStorage.isReal
        HStack(spacing: 6) {
            Image(systemName: real ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
            if real {
                Text("REAL ride store: test writes are refused").bold()
            } else {
                Text("Isolated store \(DevStorage.launchID?.prefix(8) ?? "")… (\(DevStorage.launch.source.rawValue))")
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(real ? Color.red.opacity(0.85) : Color.green.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("devToolsStorageBanner")
    }
}

// MARK: - Performance

private struct PerformancePage: View {
    let sampler: DevPerfSampler

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let samples = sampler.samples
                let last = samples.last
                HStack {
                    metric("FPS", last.map { String(format: "%.0f", $0.fps) })
                    metric("Mem", last.map { String(format: "%.0f MB", $0.memoryMB) })
                    metric("CPU", last.map { String(format: "%.0f%%", $0.cpuPercent) })
                    metric("Hitch/s", last.map { "\($0.hitches)" })
                }
                chart("FPS", samples, \.fps, color: .green)
                chart("Memory MB", samples, \.memoryMB, color: .orange)
                chart("CPU %", samples, \.cpuPercent, color: .cyan)
                Chart(samples) { sample in
                    BarMark(x: .value("t", sample.id), y: .value("Hitches", sample.hitches))
                        .foregroundStyle(.red)
                }
                .chartXAxis(.hidden)
                .frame(height: 50)
                .overlay(alignment: .topLeading) { Text("Hitches (longest frame \(String(format: "%.0f", samples.map(\.longestFrameMs).max() ?? 0)) ms)").font(.caption2) }
                SignpostList()
            }
        }
    }

    private func metric(_ name: String, _ value: String?) -> some View {
        VStack {
            Text(value ?? "–").font(.callout.monospacedDigit().bold())
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func chart(_ title: String, _ samples: [DevPerfSampler.Sample],
                       _ value: KeyPath<DevPerfSampler.Sample, Double>, color: Color) -> some View {
        Chart(samples) { sample in
            LineMark(x: .value("t", sample.id), y: .value(title, sample[keyPath: value]))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .frame(height: 56)
        .overlay(alignment: .topLeading) { Text(title).font(.caption2) }
    }
}

private struct SignpostList: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let aggregates = SignpostRecorder.shared.aggregates().prefix(24)
            let recent = SignpostRecorder.shared.recent(12)
            VStack(alignment: .leading, spacing: 3) {
                Text("Signposts (count · last · mean · max ms)").font(.caption.bold())
                if aggregates.isEmpty { Text("No intervals recorded yet").foregroundStyle(.secondary) }
                ForEach(Array(aggregates), id: \.name) { item in
                    HStack {
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Text("\(item.count) · \(ms(item.lastMs)) · \(ms(item.meanMs)) · \(ms(item.maxMs))")
                            .monospacedDigit()
                    }
                }
                if !recent.isEmpty {
                    Text("Recent").font(.caption.bold()).padding(.top, 4)
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.name).lineLimit(1)
                            Spacer()
                            Text(ms(entry.milliseconds)).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Reset signposts") { SignpostRecorder.shared.reset() }.padding(.top, 4)
            }
        }
    }

    private func ms(_ value: Double) -> String { String(format: value < 10 ? "%.2f" : "%.0f", value) }
}

// MARK: - Triggers

private struct TriggersPage: View {
    let controller: DevToolsController
    @State private var confirmFreshStore = false
    private var host: AppControlHost { .shared }

    private static let testTripsKey = "devtools.testTrips"

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                trigger("Load samples (fresh store)", "tray.and.arrow.down") {
                    if DevStorage.isReal { confirmFreshStore = true } else { run("loadSamples") }
                }
                trigger("Reload all routes", "arrow.clockwise") { run("reloadAll", ["wait": false]) }
                trigger("Select random trip", "hand.tap") {
                    if let id = randomTripID() { run("selectTrip", ["id": .string(id)]) }
                }
                trigger("Focus random trip", "scope") {
                    if let id = randomTripID() { run("focusTrip", ["id": .string(id)]) }
                }
                trigger("Open editor", "pencil") {
                    if let id = host.stores?.itineraries.selectedTrainID ?? randomTripID() {
                        run("openEditor", ["id": .string(id)])
                    }
                }
                trigger("Add demo trip", "plus.circle") {
                    run("addTrip", ["from": "東京", "to": "新大阪", "date": .string(RecordDate.text(from: Date())),
                                    "save": true]) { result in
                        if let id = result.data?.object?["save"]?.object?["recordID"]?.string { remember(id) }
                    }
                }
                trigger("Delete last test trip", "trash") {
                    guard let id = testTrips.last else { controller.lastMessage = "No test trip added from here"; return }
                    run("deleteTrip", ["id": .string(id)]) { result in
                        if result.status == .ok || result.error?.hasPrefix("not found") == true { forget(id) }
                    }
                }
                trigger("Open Stats", "chart.bar") { run("openStats") }
                trigger("Toggle hide filter", "eye.slash") {
                    let hidden = host.stores.map { !$0.tripHide.hiddenRegions.isEmpty || !$0.tripHide.hiddenYears.isEmpty
                        || !$0.tripHide.hiddenMonths.isEmpty } ?? false
                    if hidden { run("setHideFilter", ["mode": "showAll"]) }
                    else { run("setHideFilter", ["years": .array([.number(Double(Calendar.current.component(.year, from: Date())))])]) }
                }
                trigger("Screenshot", "camera") { run("screenshot") }
            }
            ResultsList(message: controller.lastMessage)
        }
        .alert("Switch to a fresh isolated store?", isPresented: $confirmFreshStore) {
            Button("Switch and quit") {
                DevStorage.setOverride(UUID().uuidString)
                DevStorage.setPendingCommand(AppControlRequest(id: "dev-pending-\(UUID().uuidString.prefix(8))", command: "loadSamples"))
                UserDefaults.standard.synchronize()  // flush before the hard exit
                exit(0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app is on the real ride store. It will quit; reopen it to load the samples into a new UUID store. Tools ▸ Real store switches back.")
        }
    }

    private func trigger(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .padding(.horizontal, 8)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func run(_ command: String, _ args: [String: AppControlJSON] = [:],
                     then: (@MainActor (AppControlResult) -> Void)? = nil) {
        controller.lastMessage = "\(command)…"
        host.submit(command, args: args) { result in
            controller.lastMessage = "\(command): \(result.status.rawValue) \(Int(result.elapsedMs ?? 0)) ms"
                + (result.error.map { " — \($0)" } ?? "")
            then?(result)
        }
    }

    private func randomTripID() -> String? {
        let id = host.stores?.itineraries.loaded?.trains.randomElement()?.id
        if id == nil { controller.lastMessage = "No trips loaded" }
        return id
    }

    private var storeKey: String { "\(Self.testTripsKey).\(DevStorage.launchID ?? "real")" }
    private var testTrips: [String] { UserDefaults.standard.stringArray(forKey: storeKey) ?? [] }
    private func remember(_ id: String) { UserDefaults.standard.set(testTrips + [id], forKey: storeKey) }
    private func forget(_ id: String) { UserDefaults.standard.set(testTrips.filter { $0 != id }, forKey: storeKey) }
}

private struct ResultsList: View {
    let message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message { Text(message).bold().fixedSize(horizontal: false, vertical: true) }
            ForEach(AppControlHost.shared.recentResults.prefix(8), id: \.id) { result in
                Text("\(result.command) · \(result.status.rawValue) · \(Int(result.elapsedMs ?? 0)) ms")
                    .foregroundStyle(result.status == .ok ? Color.secondary : Color.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// MARK: - State

private struct StatePage: View {
    @State private var caches: [(String, String)] = []

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let rows = rows()
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top) {
                            Text(row.0).foregroundStyle(.secondary)
                            Spacer()
                            Text(row.1).multilineTextAlignment(.trailing).monospacedDigit()
                        }
                    }
                }
            }
            Divider().overlay(.white.opacity(0.3))
            VStack(alignment: .leading, spacing: 3) {
                Button("Measure cache sizes") {
                    Task {
                        caches = await Task.detached(priority: .utility) {
                            DevJSONRows.flatten(AppControlHost.caches(), prefix: "")
                        }.value
                    }
                }
                ForEach(Array(caches.enumerated()), id: \.offset) { _, row in
                    HStack { Text(row.0).foregroundStyle(.secondary); Spacer(); Text(row.1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rows() -> [(String, String)] {
        guard let stores = AppControlHost.shared.stores else { return [("app", "not mounted")] }
        guard case .object(var state) = AppControlHost.shared.state(stores, includeTrips: false, includeCaches: false)
        else { return [] }
        state.removeValue(forKey: "signposts")
        state.removeValue(forKey: "root")
        var rows = DevJSONRows.flatten(.object(state), prefix: "")
        let recorder = SignpostRecorder.shared
        for name in ["map.rebuild", "map.tapIndex.build", "map.tapIndex.prebuild", "map.tap", "route.cacheRead"] {
            if let item = recorder.aggregate(named: name) {
                rows.append(("\(name)", "\(item.count)× last \(String(format: "%.1f", item.lastMs)) ms"))
            }
        }
        if !recorder.isActive { rows.append(("signposts", "recorder off")) }
        return rows
    }
}

enum DevJSONRows {
    static func flatten(_ value: AppControlJSON, prefix: String) -> [(String, String)] {
        switch value {
        case .object(let object):
            return object.keys.sorted().flatMap { key in
                flatten(object[key]!, prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
            }
        case .array(let array): return [(prefix, "\(array.count) items")]
        case .null: return [(prefix, "–")]
        case .bool(let flag): return [(prefix, flag ? "yes" : "no")]
        case .number(let number):
            return [(prefix, number.rounded() == number ? String(Int64(number)) : String(format: "%.1f", number))]
        case .string(let text): return [(prefix, text)]
        }
    }
}

// MARK: - Tools

private struct ToolsPage: View {
    let controller: DevToolsController
    @State private var relaunch: String?
    private var host: AppControlHost { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section("Ride store") {
                    Text("Now: \(DevStorage.launchID ?? "REAL") (\(DevStorage.launch.source.rawValue))")
                        .textSelection(.enabled)
                    if let pending = DevStorage.pendingOverride, pending != DevStorage.launchID {
                        Text("Next launch: \(pending)").foregroundStyle(.yellow)
                    }
                    HStack {
                        Button("New isolated store") {
                            DevStorage.setOverride(UUID().uuidString)
                            relaunch = "Next launch uses a new, empty isolated store."
                        }
                        Button("Real store") {
                            DevStorage.setOverride(nil)
                            relaunch = "Next launch uses the REAL ride store."
                        }
                        .tint(.red)
                    }
                    if DevStorage.launch.source == .environment {
                        Text("This launch's store came from the launch environment, which overrides the panel.")
                            .foregroundStyle(.secondary)
                    }
                }
                section("Caches and memory") {
                    HStack {
                        Button("Clear route caches") { run("clearRouteCaches") }
                        Button("Memory warning") { run("memoryWarning") }
                    }
                }
                section("Map layers") {
                    if let controller = host.stores?.controller {
                        LayerToggles(controller: controller, run: run)
                    }
                }
                section("Diagnostics") {
                    HStack {
                        Button("Export bundle") { run("exportDiagnostics") }
                        Button("Hide ball") { controller.setExpanded(false); controller.setVisible(false) }
                    }
                    Text("Exports go to Application Support/RailMapAppControl/exports; pull with app-control.py devtools export.")
                        .foregroundStyle(.secondary)
                }
                ResultsList(message: controller.lastMessage)
            }
            .buttonStyle(.bordered)
        }
        .alert("Restart to switch stores", isPresented: Binding(get: { relaunch != nil }, set: { if !$0 { relaunch = nil } })) {
            Button("Quit now") {
                UserDefaults.standard.synchronize()  // flush before the hard exit
                exit(0)
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text((relaunch ?? "") + " The stores are built once at launch, so the app has to be reopened.")
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func run(_ command: String, _ args: [String: AppControlJSON] = [:]) {
        controller.lastMessage = "\(command)…"
        host.submit(command, args: args) { result in
            controller.lastMessage = "\(command): \(result.status.rawValue) \(Int(result.elapsedMs ?? 0)) ms"
                + (result.error.map { " — \($0)" } ?? "")
        }
    }
}

private struct LayerToggles: View {
    let controller: RailMapController
    let run: (String, [String: AppControlJSON]) -> Void

    var body: some View {
        let layers = controller.layers
        let values: [(String, Bool)] = [
            ("routes", layers.routes), ("stops", layers.stops), ("terminals", layers.terminals),
            ("pass", layers.passThrough), ("hsr", layers.categories.hsr), ("jr", layers.categories.jr),
            ("metro", layers.categories.metro), ("priv", layers.categories.priv), ("network", controller.showsNetwork),
        ]
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            ForEach(values, id: \.0) { name, on in
                Toggle(name, isOn: Binding(get: { on }, set: { run("setLayer", ["name": .string(name), "on": .bool($0)]) }))
                    .toggleStyle(.button)
            }
        }
    }
}

// MARK: - Logs

private struct LogsPage: View {
    @State private var lines: [DevDiagnostics.LogLine] = []
    @State private var filter = ""
    @State private var loading = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { line in
                        Text("\(line.date.formatted(date: .omitted, time: .standard)) [\(line.category)] \(line.message)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(line.level == "error" || line.level == "fault" ? Color.orange : Color.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .task { await load() }
    }

    private var shown: [DevDiagnostics.LogLine] {
        let wanted = filter.trimmingCharacters(in: .whitespaces)
        let matching = wanted.isEmpty ? lines : lines.filter {
            $0.message.localizedCaseInsensitiveContains(wanted) || $0.category.localizedCaseInsensitiveContains(wanted)
        }
        return matching.reversed()
    }

    private func load() async {
        loading = true
        lines = await DevDiagnostics.logs()
        loading = false
    }
}
#endif
