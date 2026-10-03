import Testing
import RailCore
@testable import RailPresentation

struct JourneyRouteIdentityTests {
    @Test func pendingPhysicalHintsAndStaleDetectionDoNotClaimTraversedLines() {
        var pending = train(type: "普通", lines: ["東海道線"])
        pending.routeConfirmation = .pending
        let stale = [Statistics.TraversedLine(name: "総武線", operatorName: "JR東日本", km: 8,
                                             selectedLineID: "sourced-line")]
        #expect(JourneyRouteIdentity.recordedLineNames(of: pending).isEmpty)
        #expect(JourneyRouteIdentity.lineNames(of: pending, detected: stale).isEmpty)
        #expect(!JourneyRouteIdentity.detectedApplies(pending, detected: stale))
        #expect(JourneyRouteIdentity.operatorNames(of: pending, detected: stale) == ["JR東日本"])
    }
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

    @Test func namedExpressWithoutServiceLogoUsesOperatorThenTrainGlyph() {
        var consultedLine = false
        func lineLogo() -> String? { consultedLine = true; return "/rail/logos/line.png" }
        var express = train(type: "特急", lines: ["東海道線"])
        express.number = "サンライズ出雲1号"
        #expect(JourneyRouteIdentity.logoPath(
            for: express, lineLogo: lineLogo(),
            operatorLogo: "/rail/operator-logos/jr-west.png")
            == "/rail/operator-logos/jr-west.png")
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

    @Test(arguments: [
        ("WEST EXPRESS 銀河1号", "/rail/service-logos/west-express-ginga.png"),
        ("はこね3号", "/rail/service-logos/romancecar.png"),
        ("メトロホームウェイ41号", "/rail/service-logos/romancecar.png"),
        ("はるか12号", "/rail/service-logos/haruka.jpg"),
        ("オーシャンアロー3号", "/rail/service-logos/ocean-arrow.jpg"),
        ("スノーモンキー1号", "/rail/service-logos/snow-monkey.jpg"),
    ])
    func newlyCatalogedServiceMarksResolve(number: String, expectedPath: String) {
        var express = train(type: "特急", lines: ["小田原線"])
        express.number = number
        #expect(JourneyRouteIdentity.logoPath(
            for: express, lineLogo: nil, operatorLogo: "/rail/operator-logos/operator.png")
            == expectedPath)
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

    @Test func selectedPhysicalRouteOverridesOrdinaryRecordedLine() {
        let local = train(type: "普通", lines: ["山手線"])
        let selected = [Statistics.TraversedLine(
            name: "東北線", operatorName: "東日本旅客鉄道", km: 5,
            selectedLineID: "jp-東日本旅客鉄道-東北線")]
        #expect(JourneyRouteIdentity.detectedApplies(local, detected: selected))
        #expect(JourneyRouteIdentity.lineNames(of: local, detected: selected) == ["東北線"])
        #expect(JourneyRouteIdentity.operatorNames(of: local, detected: selected) == ["東日本旅客鉄道"])
    }

    @Test func partialSelectedRouteDoesNotInventUnresolvedRecordedLegs() {
        var local = train(type: "普通 直通", lines: ["東横線", "副都心線"])
        local.routePolicy = RoutePolicy(preferredLineNames: ["東横線", "日比谷線"])
        let selected = [Statistics.TraversedLine(
            name: "副都心線", operatorName: "東京メトロ", km: 12,
            selectedLineID: "jp-東京地下鉄-副都心線")]
        #expect(JourneyRouteIdentity.lineNames(of: local, detected: selected) == ["副都心線"])
        #expect(JourneyRouteIdentity.operatorNames(of: local, detected: selected) == ["東京メトロ"])
    }

    @Test func selectedOperatorsKeepPhysicalTraversalOrderAndRemoveDuplicates() {
        let local = train(type: "普通", lines: ["Recorded"])
        let selected = [
            Statistics.TraversedLine(name: "A", operatorName: "Operator B", km: 1, selectedLineID: "a"),
            Statistics.TraversedLine(name: "B", operatorName: "Operator A", km: 2, selectedLineID: "b"),
            Statistics.TraversedLine(name: "A", operatorName: "Operator B", km: 3, selectedLineID: "a"),
        ]
        #expect(JourneyRouteIdentity.lineNames(of: local, detected: selected) == ["A", "B"])
        #expect(JourneyRouteIdentity.operatorNames(of: local, detected: selected) == ["Operator B", "Operator A"])
    }

    @Test func emptySelectedDetectionKeepsExistingRecordedIdentityAndCompany() {
        let local = train(type: "普通", lines: ["山手線"])
        #expect(!JourneyRouteIdentity.detectedApplies(local, detected: []))
        #expect(JourneyRouteIdentity.lineNames(of: local, detected: []) == ["山手線"])
        #expect(JourneyRouteIdentity.operatorNames(of: local, detected: []) == ["JR東日本"])
    }
}
