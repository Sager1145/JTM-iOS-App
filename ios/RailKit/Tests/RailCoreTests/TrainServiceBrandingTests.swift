import RailCore
import Testing

struct TrainServiceBrandingTests {
    private static func train(
        number: String,
        numberEn: String? = nil,
        trainType: String? = nil,
        company: String? = nil,
        region: String? = "jp",
        routePolicy: RoutePolicy? = nil,
        routeSections: [RouteSection]? = nil
    ) -> Train {
        Train(
            id: "test", number: number, numberEn: numberEn, trainType: trainType,
            company: company, origin: "A", destination: "B",
            routePolicy: routePolicy, routeSections: routeSections,
            stops: [Stop(name: "A"), Stop(name: "B")], region: region)
    }

    @Test("the bundled catalog has stable unique identities")
    func catalogLoads() {
        let services = TrainServiceBranding.services
        #expect(services.count >= 100)
        #expect(Set(services.map(\.id)).count == services.count)
        #expect(services.allSatisfy { $0.region.isEmpty == false && $0.names.isEmpty == false })
    }

    @Test(arguments: [
        ("はるか38号（1038M）", nil, "haruka"),
        ("はるか号", nil, "haruka"),
        ("臨時列車", "ＨＡＲＵＫＡ　３８", "haruka"),
        ("特急 サフィール踊り子3号", nil, "saphir-odoriko"),
        ("N'EX 12", nil, "narita-express"),
        ("寝台特急サンライズ出雲91号", nil, "sunrise-izumo"),
        ("臨時列車", "Nanpū 5", "nanpu"),
    ])
    func matchesNativeLatinFullWidthAndNumberSuffix(
        number: String, numberEn: String?, expectedID: String
    ) {
        #expect(TrainServiceBranding.service(for: Self.train(
            number: number, numberEn: numberEn))?.id == expectedID)
    }

    @Test("a shorter name and a foreign region cannot steal a match")
    func matchingIsUnambiguousAndRegionScoped() {
        #expect(TrainServiceBranding.service(for: Self.train(number: "Fujinomiya 3")) == nil)
        #expect(TrainServiceBranding.service(for: Self.train(
            number: "Haruka 38", region: "tw")) == nil)
        #expect(TrainServiceBranding.service(for: Self.train(
            number: "サフィール踊り子3号"))?.id == "saphir-odoriko")
    }

    @Test("legacy regionless Japanese records still resolve")
    func missingRegionUsesJapaneseCatalog() {
        #expect(TrainServiceBranding.service(for: Self.train(
            number: "Thunderbird 7", region: nil))?.id == "thunderbird")
    }

    @Test("limited express classification accepts type, caption, and known service")
    func limitedExpressClassification() {
        #expect(TrainServiceBranding.isLimitedExpress(Self.train(
            number: "Unknown 1", trainType: "特急")))
        #expect(TrainServiceBranding.isLimitedExpress(Self.train(
            number: "Limited Express Mystery 1")))
        #expect(TrainServiceBranding.isLimitedExpress(Self.train(number: "あずさ5号")))
        #expect(TrainServiceBranding.isLimitedExpress(Self.train(
            number: "Mystery 1", trainType: "Special")) == false)
        #expect(TrainServiceBranding.isLimitedExpress(Self.train(
            number: "中央線", trainType: "特別快速")) == false)
    }

    @Test("express and explicitly through-running services use detected lines")
    func serviceSignalsUseDetectedLines() {
        #expect(TrainServiceBranding.usesDetectedLines(Self.train(
            number: "Mystery", trainType: "快速")))
        #expect(TrainServiceBranding.usesDetectedLines(Self.train(
            number: "普通（東京メトロ千代田線から直通）", trainType: "普通")))
        #expect(TrainServiceBranding.usesDetectedLines(Self.train(
            number: "Local through service", trainType: "Local")))
        #expect(TrainServiceBranding.usesDetectedLines(Self.train(
            number: "Local through-running", trainType: "Local")))
    }

    @Test("distinct recorded route sections are cross-line evidence")
    func distinctRecordedRoutesUseDetectedLines() {
        let crossLine = Self.train(
            number: "Local", trainType: "Local",
            routeSections: [
                RouteSection(lineNames: ["高崎線"], operatorNames: ["東日本旅客鉄道"]),
                RouteSection(lineNames: ["東海道線"], operatorNames: ["JR東日本"]),
            ])
        let repeatedSingleLine = Self.train(
            number: "Local", trainType: "Local", company: "JR東日本",
            routeSections: [
                RouteSection(lineNames: ["山手線"], operatorNames: ["東日本旅客鉄道"]),
                RouteSection(lineNames: ["山手線"], operatorNames: ["JR東日本"]),
            ])

        #expect(TrainServiceBranding.usesDetectedLines(crossLine))
        #expect(TrainServiceBranding.usesDetectedLines(repeatedSingleLine) == false)
    }

    @Test("broad policy alternatives do not override an explicit single line")
    func explicitSectionsWinOverPolicyAlternatives() {
        let train = Self.train(
            number: "Local", trainType: "Local",
            routePolicy: RoutePolicy(preferredLineNames: ["宮崎空港線", "日南線", "日豊線"]),
            routeSections: [RouteSection(lineNames: ["日豊線"])]
        )
        #expect(TrainServiceBranding.usesDetectedLines(train) == false)
    }

    @Test("an unknown single-line service keeps its recorded identity")
    func unknownSingleLineKeepsRecordedLine() {
        let train = Self.train(
            number: "Mystery", trainType: "Special",
            routeSections: [RouteSection(lineNames: ["山手線"])]
        )
        #expect(TrainServiceBranding.usesDetectedLines(train) == false)
    }

    @Test("policy-only lines are never cross-line evidence")
    func policyOnlyLinesAreNotCrossLineEvidence() {
        let train = Self.train(
            number: "Local", trainType: "Local",
            routePolicy: RoutePolicy(preferredLineNames: ["宮崎空港線", "日南線", "日豊線"])
        )
        #expect(TrainServiceBranding.usesDetectedLines(train) == false)
    }

    @Test("train.company is never cross-line operator evidence")
    func companyIsNotCrossLineOperatorEvidence() {
        let train = Self.train(
            number: "Local", trainType: "Local", company: "JR East",
            routeSections: [RouteSection(lineNames: ["山手線"], operatorNames: ["東日本旅客鉄道"])]
        )
        #expect(TrainServiceBranding.usesDetectedLines(train) == false)
    }

    @Test("distinct recorded operators across sections are cross-line evidence")
    func distinctRecordedOperatorsUseDetectedLines() {
        let train = Self.train(
            number: "Local", trainType: "Local",
            routeSections: [
                RouteSection(lineNames: ["山手線"], operatorNames: ["東日本旅客鉄道"]),
                RouteSection(lineNames: ["山手線"], operatorNames: ["東海旅客鉄道"]),
            ]
        )
        #expect(TrainServiceBranding.usesDetectedLines(train))
    }

    @Test("特快 is a limited express only in tw/hk/mo, not jp's 特別快速")
    func tekkuaiIsRegionScoped() {
        #expect(TrainServiceBranding.isLimitedExpress(Self.train(
            number: "中央特快", trainType: "中央特快", region: "jp")) == false)
        #expect(TrainServiceBranding.isLimitedExpress(Self.train(
            number: "特快", trainType: "特快", region: "tw")))
    }

    @Test(arguments: [
        "for Shin-Hakodate-Hokuto",
        "Kinosaki-Onsen",
        "Hida-Furukawa",
        "Fuji Kyuko Line",
        "Shinano Railway",
        "Soya Line Local",
    ])
    func latinLeadingNamesNeedTrainNumberContext(caption: String) {
        #expect(TrainServiceBranding.service(for: Self.train(number: caption)) == nil)
    }

    @Test(arguments: [
        ("N'EX 12", "narita-express"),
        ("Haruka 38", "haruka"),
        ("ＨＡＲＵＫＡ　３８", "haruka"),
        ("Nanpū 5", "nanpu"),
        ("Thunderbird 7", "thunderbird"),
        ("Narita Express", "narita-express"),
        ("Hokuto 5 (Sapporo)", "hokuto"),
    ])
    func latinLeadingNamesResolveWithTrainNumberContext(caption: String, expectedID: String) {
        #expect(TrainServiceBranding.service(for: Self.train(number: caption))?.id == expectedID)
    }

    @Test(arguments: [
        ("スーパーはくと5号", "super-hakuto"),
        ("特急ソニック21号", "sonic"),
        ("あそぼーい！101号", "asoboy"),
        ("あそ1号", "aso"),
        ("Fujisan 3", "fujisan"),
        ("Fuji Excursion 5", "fuji-excursion"),
        ("新宿さざなみ1号", "shinjuku-sazanami"),
        ("さざなみ3号", "sazanami"),
        ("かんぱち", "kanpachi-ichiroku"),
        ("ゆふいんの森3号", "yufuin-no-mori"),
        ("ゆふ1号", "yufu"),
        ("にちりんシーガイア5号", "nichirin-seagaia"),
        ("Spacia Nikko 1", "spacia-nikko"),
        ("TWILIGHT EXPRESS 瑞風", "twilight-express-mizukaze"),
    ])
    func jrLimitedExpressNamesResolve(caption: String, expectedID: String) {
        #expect(TrainServiceBranding.service(for: Self.train(number: caption))?.id == expectedID)
    }

    @Test(arguments: [
        "日光線（宇都宮→日光）",
        "東海道線（沼津→富士）",
        "函館本線（新函館北斗→函館）",
        "ゆりかもめ（新橋→有明）",
    ])
    func directionalRouteBracketsAreNotTheServiceName(caption: String) {
        let train = Self.train(number: caption, trainType: "普通")
        #expect(TrainServiceBranding.service(for: train) == nil)
        #expect(TrainServiceBranding.isLimitedExpress(train) == false)
    }

    @Test(arguments: [
        ("特急日光1号（新宿→東武日光）", "nikko"),
        ("北斗5号（函館→札幌）", "hokuto"),
    ])
    func nameBesideADirectionalBracketStillResolves(caption: String, expectedID: String) {
        #expect(TrainServiceBranding.service(for: Self.train(number: caption))?.id == expectedID)
    }

    @Test(arguments: [
        "Local for Aso",
        "Rapid for Ome",
    ])
    func forToBoundBeforeAnEndOfCaptionNameIsNotTrainNumberContext(caption: String) {
        #expect(TrainServiceBranding.service(for: Self.train(number: caption)) == nil)
    }

    @Test(arguments: [
        ("Aso 1", "aso"),
        ("Narita Express", "narita-express"),
    ])
    func endOfCaptionNameWithoutABoundMarkerStillResolves(caption: String, expectedID: String) {
        #expect(TrainServiceBranding.service(for: Self.train(number: caption))?.id == expectedID)
    }

    @Test("本線 and its 線 form fold together for cross-line detection")
    func honsenAndSenFormsFoldTogetherForCrossLineDetection() {
        let train = Self.train(
            number: "Local", trainType: "普通",
            routeSections: [
                RouteSection(lineNames: ["東海道本線"]),
                RouteSection(lineNames: ["東海道線"]),
            ])
        #expect(TrainServiceBranding.usesDetectedLines(train) == false)
    }
}
