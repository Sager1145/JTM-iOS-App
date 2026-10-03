import Foundation
import SQLite3
import Testing
@testable import RailCore

@Suite("Official journey English name")
struct JourneyEnglishNameTests {
    private func train(_ name: String, date: String? = nil, english: String? = nil,
                       region: String = "jp") -> Train {
        var train = Train(id: "name", date: date, number: name, origin: "", destination: "", stops: [], region: region)
        train.numberEn = english
        return train
    }

    private func fixture() throws -> FixtureDatabase {
        let fixture = try FixtureDatabase()
        var connection: OpaquePointer?
        guard sqlite3_open(fixture.url.path, &connection) == SQLITE_OK, let connection else {
            throw FixtureDatabase.FixtureError.sqlite("open")
        }
        defer { sqlite3_close(connection) }
        let sql = """
            INSERT INTO services VALUES('haruka','はるか','limited_express',1,NULL,NULL,'jr');
            INSERT INTO service_name_periods VALUES('haruka','はるか','ja','1990-01-01',NULL);
            INSERT INTO service_name_periods VALUES('haruka','Haruka','en','1990-01-01','2020-01-01');
            INSERT INTO service_name_periods VALUES('haruka','Haruka Express','en','2020-01-01',NULL);
            INSERT INTO service_name_periods VALUES('haruka','関空特急はるか','ja','1990-01-01',NULL);
            INSERT INTO services VALUES('missing','名前なし','limited_express',1,NULL,NULL,'jr');
            INSERT INTO services VALUES('ambiguous-a','同名','limited_express',1,NULL,NULL,'jr');
            INSERT INTO services VALUES('ambiguous-b','同名','limited_express',2,NULL,NULL,'jr');
            INSERT INTO service_name_periods VALUES('ambiguous-a','First','en','1990-01-01',NULL);
            INSERT INTO service_name_periods VALUES('ambiguous-b','Second','en','1990-01-01',NULL);
            """
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureDatabase.FixtureError.sqlite("insert")
        }
        return fixture
    }

    @Test func captionsResolveWithoutStopsOrDatesAndPreserveNumbers() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        #expect(try JourneyEnglishName.official(for: train("はるか38号 (1038M)"), database: database)
                == "Haruka Express 38 (1038M)")
        #expect(try JourneyEnglishName.official(for: train("はるか38号 (Haruka 38) (1038M)"), database: database)
                == "Haruka Express 38 (1038M)")
        #expect(try JourneyEnglishName.official(for: train("特急 関空特急はるか ３８号"), database: database)
                == "Haruka Express 38")
        #expect(try JourneyEnglishName.official(for: train("スーパーしなの1号"), database: database) == "Shinano 1")
    }

    @Test func dateUsesEnglishNamePeriodAndUndatedUsesLatest() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        #expect(try JourneyEnglishName.official(for: train("はるか38号", date: "2019-12-31"), database: database) == "Haruka 38")
        #expect(try JourneyEnglishName.official(for: train("はるか38号", date: "2020-01-01"), database: database) == "Haruka Express 38")
        #expect(try JourneyEnglishName.official(for: train("はるか", date: "1989-01-01"), database: database) == nil)
    }

    @Test func ambiguousMissingAndUnrelatedCaptionsStayUntranslated() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        for name in ["同名1号", "名前なし", "はるかぜ38号", "私の旅 (はるか38号)", "my journey"] {
            #expect(try JourneyEnglishName.official(for: train(name, english: "Haruka 38"), database: database) == nil)
        }
        #expect(try JourneyEnglishName.official(for: train("はるか38号", english: "My custom name"), database: database) == "Haruka Express 38")
        #expect(try JourneyEnglishName.official(for: train("はるか38号", region: "tw"), database: database) == nil)
    }
}
