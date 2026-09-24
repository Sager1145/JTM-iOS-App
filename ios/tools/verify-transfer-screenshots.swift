import Foundation
import RailCore

private struct Input: Encodable {
    var argument: String
    var name: String
}

private struct Box: Encodable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ box: TransferGuide.Box) {
        x = box.x
        y = box.y
        width = box.width
        height = box.height
    }
}

private struct RawLine: Encodable {
    var text: String
    var box: Box
    var confidence: Double

    init(_ line: TransferGuide.TextLine) {
        text = line.text
        box = Box(line.box)
        confidence = line.confidence
    }
}

private struct Source: Encodable {
    var id: String
    var label: String
}

private struct Header: Encodable {
    var departure: String?
    var arrival: String?
    var durationMinutes: Int?
    var month: Int?
    var day: Int?
    var year: Int?
    var weekday: String?
    var fareYen: Int?
    var transferCount: Int?
    var distanceKm: Double?

    init(_ header: TransferGuide.Header) {
        departure = header.departure
        arrival = header.arrival
        durationMinutes = header.durationMinutes
        month = header.month
        day = header.day
        year = header.year
        weekday = header.weekday
        fareYen = header.fareYen
        transferCount = header.transferCount
        distanceKm = header.distanceKm
    }
}

private struct Stop: Encodable {
    var name: String
    var qualifier: String?
    var rawName: String
    var arrival: String?
    var departure: String?

    init(_ call: TransferGuide.Call) {
        name = call.name
        qualifier = call.qualifier
        rawName = call.rawName
        arrival = call.arrival
        departure = call.departure
    }
}

private struct Leg: Encodable {
    var kind: String
    var service: String
    var throughServices: [String]
    var destination: String?
    var equipment: String?
    var startsHere: Bool
    var departurePlatform: Int?
    var arrivalPlatform: Int?
    var carCount: Int?
    var declaredStationCount: Int?
    var fareYen: Int?
    var notes: [String]
    var stops: [Stop]

    init(_ leg: TransferGuide.Leg) {
        kind = leg.kind.rawValue
        service = leg.service
        throughServices = leg.throughServices
        destination = leg.destination
        equipment = leg.equipment
        startsHere = leg.startsHere
        departurePlatform = leg.departurePlatform
        arrivalPlatform = leg.arrivalPlatform
        carCount = leg.carCount
        declaredStationCount = leg.declaredStationCount
        fareYen = leg.fareYen
        notes = leg.notes
        stops = leg.calls.map(Stop.init)
    }
}

private struct Time: Encodable {
    var leg: Int
    var stop: Int
    var station: String
    var arrival: String?
    var departure: String?
}

private struct Note: Encodable {
    var kind: String
    var subject: String
}

private struct Output: Encodable {
    var inputs: [Input]
    var pageCount: Int
    var tileCount: Int
    var documentWidth: Double
    var documentHeight: Double
    var source: Source
    var header: Header
    var rawRows: [String]
    var rawLines: [RawLine]
    var legs: [Leg]
    var times: [Time]
    var notes: [Note]
    var unclaimed: [String]
}

private enum HarnessError: LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        "The screenshot harness expected display-name/path argument pairs."
    }
}

@main
private struct VerifyTransferScreenshots {
    static func main() async {
        do {
            try await run()
        } catch {
            let message = "verify-transfer-screenshots: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else {
            throw HarnessError.invalidArguments
        }

        var inputs: [Input] = []
        var pages: [Data] = []
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let argument = arguments[index]
            let path = arguments[index + 1]
            inputs.append(Input(argument: argument, name: URL(fileURLWithPath: path).lastPathComponent))
            pages.append(try Data(contentsOf: URL(fileURLWithPath: path)))
        }

        let reading = try await TransferGuideOCR.read(pages) { done, total in
            guard done == 0 || done == total else { return }
            let message = "OCR tiles: \(done)/\(total)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        let read = TransferGuide.read(reading.lines)
        let route = read.route
        var times: [Time] = []
        for (legIndex, leg) in route.legs.enumerated() {
            for (stopIndex, stop) in leg.calls.enumerated()
            where stop.arrival != nil || stop.departure != nil {
                times.append(Time(
                    leg: legIndex,
                    stop: stopIndex,
                    station: stop.name,
                    arrival: stop.arrival,
                    departure: stop.departure))
            }
        }

        let output = Output(
            inputs: inputs,
            pageCount: reading.pageCount,
            tileCount: reading.tileCount,
            documentWidth: reading.documentWidth,
            documentHeight: reading.documentHeight,
            source: Source(id: read.source.rawValue, label: read.source.label),
            header: Header(route.header),
            rawRows: reading.rawRows,
            rawLines: reading.lines.map(RawLine.init),
            legs: route.legs.map(Leg.init),
            times: times,
            notes: route.notes.map { Note(kind: $0.kind.rawValue, subject: $0.subject) },
            unclaimed: route.unclaimed)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
