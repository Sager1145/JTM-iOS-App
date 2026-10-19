import SwiftUI
import MapKit
import WorkbenchCore

struct PatternDetailView: View {
    let pattern: PatternSummary
    let snapshot: WorkbenchSnapshot?
    let day: String
    let edit: () -> Void

    var body: some View {
        List {
            Section {
                LabeledContent("Pattern ID", value: pattern.id)
                LabeledContent("Service code", value: pattern.serviceCode)
                LabeledContent("Status on \(day)", value: pattern.statusLabel)
                if !pattern.notes.isEmpty { Text(pattern.notes).textSelection(.enabled) }
                Button("Create dated patch", action: edit)
            }
            Section("Corridor reference geometry") {
                CorridorMap(legs: pattern.legs)
                    .id(pattern.id)
                    .frame(minHeight: 280, idealHeight: 340)
                    .listRowInsets(EdgeInsets())
                Text("Selected leg geometry is a reference for review. Through-service relationships do not establish physical railway connections.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Legs (\(pattern.legs.count))") {
                ForEach(pattern.legs) { leg in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(leg.index + 1). \(leg.lineID)").font(.headline).textSelection(.enabled)
                        Text("\(leg.fromName) [\(leg.fromStationCode)] → \(leg.toName) [\(leg.toStationCode)]")
                            .textSelection(.enabled)
                        Text("\(leg.isActive ? "Active" : "Inactive") · \(leg.validFrom ?? "Unspecified start") – \(leg.validTo ?? "Open end")")
                            .font(.caption).foregroundStyle(.secondary)
                        if leg.coordinates.isEmpty { Label("No resolved reference geometry", systemImage: "questionmark.circle").font(.caption) }
                    }
                }
            }
            Section("Evidence") {
                if pattern.sourceURLs.isEmpty { Text("No source URLs recorded.") }
                ForEach(pattern.sourceURLs, id: \.self) { source in
                    if let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        Link(source, destination: url).textSelection(.enabled)
                    } else { Text(source).textSelection(.enabled) }
                }
            }
            Section("Review issues") {
                ForEach(snapshot?.issues.filter { $0.patternID == pattern.id } ?? []) { IssueRow(issue: $0) }
            }
            Section("Recorded patches") {
                ForEach(snapshot?.patches.filter { $0.patternID == pattern.id } ?? []) { patch in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(patch.effectiveFrom) – \(patch.effectiveTo ?? "Open end")").font(.headline)
                        Text(patch.note).textSelection(.enabled)
                        Text(patch.sourceURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Section("Expanded pattern JSON") {
                Text(rawText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private var rawText: String { (try? pattern.raw.data(pretty: true)).flatMap { String(data: $0, encoding: .utf8) } ?? "Cannot display JSON" }
}

struct CorridorMap: View {
    let legs: [LegSummary]
    @State private var position: MapCameraPosition = .automatic

    private func coordinates(_ leg: LegSummary) -> [CLLocationCoordinate2D] {
        leg.coordinates.compactMap { pair in
            guard pair.count >= 2, pair[0].isFinite, pair[1].isFinite,
                  (-180 ... 180).contains(pair[0]), (-90 ... 90).contains(pair[1]) else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    var body: some View {
        Map(position: $position) {
            ForEach(legs) { leg in
                MapPolyline(coordinates: coordinates(leg))
                    .stroke(leg.isActive ? Color.accentColor : Color.secondary, lineWidth: 4)
            }
        }
        .mapControls {
            MapCompass()
            #if !targetEnvironment(macCatalyst)
            MapScaleView()
            #endif
        }
        .onChange(of: legs.map(\.id)) { _, _ in position = .automatic }
        .accessibilityLabel("Reference map of selected pattern legs")
        .overlay {
            if legs.allSatisfy({ $0.coordinates.isEmpty }) {
                ContentUnavailableView("Geometry unavailable", systemImage: "map", description: Text("Review the physical line and station references for this pattern."))
                    .background(.background)
            }
        }
    }
}
