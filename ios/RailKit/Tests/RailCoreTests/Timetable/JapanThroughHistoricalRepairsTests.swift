import Foundation
import Testing
@testable import RailCore

struct JapanThroughHistoricalRepairsTests {
    @Test("Named services and predecessor identities are not backdated before their documented starts")
    func regionalOpeningConstraints() throws {
        for (id, before, start) in [
            ("odoriko-tokyo-shimoda", "1981-09-30", "1981-10-01"),
            ("odoriko-tokyo-shuzenji", "1981-09-30", "1981-10-01"),
            ("super-hakuto", "1994-12-02", "1994-12-03"),
            ("ibara-hakubi-fukuen", "1999-01-10", "1999-01-11"),
            ("wakasa-inbi-tottori", "1987-10-13", "1987-10-14"),
            ("nishikigawa-gantoku", "1987-07-24", "1987-07-25")
        ] {
            let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == id })
            #expect(pattern.legs(on: before).isEmpty)
            #expect(!pattern.legs(on: start).isEmpty)
        }
    }

    @Test("Fukutoshin retains Shibuya before the southern extension")
    func fukutoshinHistoricalEndpoints() throws {
        for id in ["fukutoshin-tobu-minatomirai", "fukutoshin-seibu-minatomirai"] {
            let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == id })
            #expect(pattern.legs(on: "2008-06-13").isEmpty)
            #expect(pattern.legs(on: "2008-06-14").count == 3)
            #expect(pattern.legs(on: "2013-03-15").last?.toStationCode == "003922")
            #expect(pattern.legs(on: "2013-03-16").last?.toStationCode == "004704")
        }
    }

    @Test("Hibiya substitutes its endpoints at the 2013 timetable boundary")
    func hibiyaEndpointSubstitution() throws {
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "hibiya-tobu-nikko" })
        #expect(pattern.legs(on: "1988-08-08").isEmpty)
        #expect(pattern.legs(on: "1996-12-31").first?.fromStationCode == "004487")
        #expect(pattern.legs(on: "2013-03-15").last?.toStationCode == "002728")
        #expect(pattern.legs(on: "2013-03-16").first?.fromStationCode == "004014")
        #expect(pattern.legs(on: "2013-03-16").last?.toStationCode == "002621")
    }

    @Test("Construction suspends Haruka and shortens Kuroshio for exactly one day")
    func umekitaConstructionDay() throws {
        let haruka = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "haruka" })
        #expect(haruka.legs(on: "2023-02-11").count == 5)
        #expect(haruka.legs(on: "2023-02-12").isEmpty)
        #expect(haruka.legs(on: "2023-02-13").count == 5)
        let kuroshio = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "kuroshio" })
        #expect(kuroshio.legs(on: "2023-02-11").first?.fromStationCode == "006079")
        #expect(kuroshio.legs(on: "2023-02-12").first?.fromStationCode == "007439")
        #expect(kuroshio.legs(on: "2023-02-12").count == 2)
        #expect(kuroshio.legs(on: "2023-02-13").first?.fromStationCode == "006079")
    }

    @Test("Airport paths respect the opening of their actual airport endpoint")
    func airportOpeningConstraints() throws {
        let fukuoka = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "fukuoka-kuko-chikuhi" })
        #expect(fukuoka.legs(on: "1993-03-02").isEmpty)
        #expect(fukuoka.legs(on: "1993-03-03").first?.fromStationCode == "009015")
        let miyazaki = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "kyushu-miyazaki-airport" })
        #expect(miyazaki.legs(on: "1996-07-17").isEmpty)
        #expect(miyazaki.legs(on: "1996-07-18").last?.toStationCode == "009968")
        let marine = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "seto-marine-liner" })
        #expect(marine.legs(on: "1988-04-09").isEmpty)
        #expect(marine.legs(on: "1996-12-31").first?.fromStationCode == "007310")
        #expect(marine.legs(on: "1996-12-31").last?.toStationCode == "008163")
    }

    @Test("Asagiri's documented Numazu corridor is available at the historical target")
    func asagiriHistoricalStart() throws {
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "odakyu-jr-asagiri-numazu" })
        #expect(pattern.legs(on: "1991-03-15").isEmpty)
        #expect(pattern.legs(on: "1991-03-16").first?.fromStationCode == "003700")
        #expect(pattern.legs(on: "1996-12-31").last?.toStationCode == "005689")
        #expect(pattern.legs(on: "2012-03-16").count == 2)
        #expect(pattern.legs(on: "2012-03-17").isEmpty)
    }

    @Test("Kuki through trains do not predate the 2006 extension")
    func kukiExtension() throws {
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "hanzomon-denentoshi-kuki" })
        #expect(pattern.legs(on: "2006-03-17").isEmpty)
        #expect(pattern.legs(on: "2006-03-18").last?.toStationCode == "002683")
    }

    @Test("Kyoto Keishin retains its historical city-hall terminus")
    func kyotoWesternExtension() throws {
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "kyoto-tozai-keishin" })
        #expect(pattern.legs(on: "1997-10-11").isEmpty)
        #expect(pattern.legs(on: "1997-10-12").first?.fromStationCode == "005960")
        #expect(pattern.legs(on: "2008-01-15").first?.fromStationCode == "005960")
        #expect(pattern.legs(on: "2008-01-16").first?.fromStationCode == "005959")
    }

    @Test("Isehara extension preserves older Hon-Atsugi through trains")
    func odakyuExtension() throws {
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "chiyoda-joban-odakyu" })
        #expect(pattern.legs(on: "2018-03-16").last?.toStationCode == "004715")
        #expect(pattern.legs(on: "2018-03-17").last?.toStationCode == "004844")
    }

    @Test("Haruka explicitly chooses alternate northern legs")
    func harukaAlternatives() throws {
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.id == "haruka" })
        #expect(pattern.legs(on: "2021-03-12").first?.fromStationCode == "005075")
        #expect(pattern.legs(on: "2021-03-13").first?.fromStationCode == "005772")
        #expect(pattern.legs(on: "2021-03-12").count == 5)
        #expect(pattern.legs(on: nil).count == 5)
        #expect(pattern.legs(on: "1996-12-31").isEmpty)
    }
}
