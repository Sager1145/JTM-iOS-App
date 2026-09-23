import Testing
import RailCore
@testable import RailPresentation

struct JourneyRouteIdentityTests {
    private func train(type: String?, lines: [String]) -> Train {
        Train(id: "service", number: "テスト123号", trainType: type, company: "JR東日本",
              origin: "A", destination: "B",
              routeSections: [RouteSection(lineNames: lines)], stops: [], region: "jp")
    }

    @Test func unbrandedExpressNeverEvaluatesLineLogo() {
        var consultedLine = false
        func lineLogo() -> String? { consultedLine = true; return "/rail/logos/line.png" }
        let express = train(type: "特急", lines: ["東海道線"])
        #expect(JourneyRouteIdentity.logoPath(
            for: express, lineLogo: lineLogo(), operatorLogo: "/rail/operator-logos/jr-east.png")
            == "/rail/operator-logos/jr-east.png")
        #expect(!consultedLine)
    }

    @Test func unbrandedExpressWithoutOperatorLogoUsesDefaultGlyph() {
        var consultedLine = false
        func lineLogo() -> String? { consultedLine = true; return "/rail/logos/line.png" }
        let express = train(type: "特急", lines: ["東海道線"])
        #expect(JourneyRouteIdentity.logoPath(
            for: express, lineLogo: lineLogo(), operatorLogo: nil) == nil)
        #expect(!consultedLine)
    }

    @Test func ordinaryServiceRetainsItsLineLogo() {
        #expect(JourneyRouteIdentity.logoPath(
            for: train(type: "普通", lines: ["山手線"]),
            lineLogo: "/rail/logos/yamanote.png",
            operatorLogo: "/rail/operator-logos/x.png") == "/rail/logos/yamanote.png")
    }

    @Test func namedServiceLogoIsIndependentOfItsRailway() {
        var express = train(type: nil, lines: ["成田線", "総武線", "山手線"])
        express.number = "成田エクスプレス12号"
        #expect(JourneyRouteIdentity.logoPath(
            for: express, lineLogo: "/rail/logos/yamanote.png", operatorLogo: nil)
            == "/rail/service-logos/narita-express.png")
    }

    @Test func brandedServiceLogoWinsOverOperatorLogo() {
        var express = train(type: nil, lines: ["成田線", "総武線", "山手線"])
        express.number = "成田エクスプレス12号"
        #expect(JourneyRouteIdentity.logoPath(
            for: express, lineLogo: "/rail/logos/yamanote.png",
            operatorLogo: "/rail/operator-logos/jr-east.png")
            == "/rail/service-logos/narita-express.png")
    }

    @Test func ordinarySharedTrackDoesNotChangeIdentity() {
        let local = train(type: "普通", lines: ["山手線"])
        let detected = [Statistics.TraversedLine(name: "東北線", operatorName: "JR東日本", km: 5)]
        #expect(JourneyRouteIdentity.lineNames(of: local, detected: detected) == ["山手線"])
    }

    @Test func partialThroughRouteKeepsRecordedLegsAndAddsOperators() {
        var local = train(type: "普通 直通", lines: ["東横線", "副都心線"])
        local.company = "東急電鉄"
        let detected = [Statistics.TraversedLine(name: "副都心線", operatorName: "東京メトロ", km: 12)]
        // Observed-first, then uncovered recorded legs.
        #expect(JourneyRouteIdentity.lineNames(of: local, detected: detected) == ["副都心線", "東横線"])
        #expect(JourneyRouteIdentity.operatorNames(of: local, detected: detected)
            == ["東急電鉄", "東京メトロ"])
    }

    @Test func absentDetectionPreservesRecordedRoute() {
        let express = train(type: "特急", lines: ["東海道線", "山陽線", "伯備線"])
        #expect(JourneyRouteIdentity.lineNames(of: express, detected: []) == ["東海道線", "山陽線", "伯備線"])
    }

    @Test func policyAlternativesDoNotInventRiddenLegs() {
        var express = train(type: "特急", lines: ["日豊線"])
        express.routePolicy = RoutePolicy(preferredLineNames: ["宮崎空港線", "日南線", "日豊線"])
        #expect(JourneyRouteIdentity.lineNames(of: express, detected: []) == ["日豊線"])
    }

    @Test func canonicalFormsCollapseHonsenAndSenDetection() {
        let express = train(type: "特急", lines: ["東海道本線", "山陽本線"])
        let detected = [
            Statistics.TraversedLine(name: "東海道線", operatorName: "JR西日本", km: 3),
            Statistics.TraversedLine(name: "山陽線", operatorName: "JR西日本", km: 4),
        ]
        #expect(JourneyRouteIdentity.lineNames(of: express, detected: detected) == ["東海道線", "山陽線"])
    }

    @Test func policyOnlyExpressUsesOnlyDetectedLine() {
        var express = train(type: "特急", lines: [])
        express.routeSections = nil
        express.routePolicy = RoutePolicy(preferredLineNames: ["宮崎空港線", "日南線", "日豊線"])
        let detected = [Statistics.TraversedLine(name: "日豊線", operatorName: "JR九州", km: 5)]
        #expect(JourneyRouteIdentity.lineNames(of: express, detected: detected) == ["日豊線"])
    }

    @Test func partialDetectionKeepsUncoveredRecordedLeg() {
        let express = train(type: "特急", lines: ["東海道線", "伯備線"])
        let detected = [Statistics.TraversedLine(name: "東海道線", operatorName: "JR西日本", km: 3)]
        #expect(JourneyRouteIdentity.lineNames(of: express, detected: detected) == ["東海道線", "伯備線"])
    }
}
