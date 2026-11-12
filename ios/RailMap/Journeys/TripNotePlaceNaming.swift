import RailCore

/// The one place a trip note's place is put into words, for the trip card and
/// the map's marker label and pick banner alike. Always the trip's own stops.
@MainActor
enum TripNotePlaceNaming {
    /// "At A", "A → B", "Pinned on map" or "No place".
    static func place(_ anchor: TripNoteAnchor, stops: [Stop], region: Region?,
                      localization: AppLocalization) -> String {
        switch TripNotePlacement.resolve(anchor, stops: stops) {
        case .station(let index):
            return localization.text("ios.tripNotes.placeAtStation", params: [
                "station": .string(stationName(stops[index], region: region, localization: localization)),
            ])
        case .interval(let from, let to, _):
            return localization.text("ios.tripNotes.placeBetween", params: [
                "from": .string(stationName(stops[from], region: region, localization: localization)),
                "to": .string(stationName(stops[to], region: region, localization: localization)),
            ])
        case .coordinate: return localization.text("ios.tripNotes.placeOnMap")
        case .unplaced: return localization.text("ios.tripNotes.placeUnplaced")
        }
    }

    static func stationName(_ stop: Stop, region: Region?, localization: AppLocalization) -> String {
        localization.stationName(stop.name, code: stop.n02StationCode, region: region)
    }
}
