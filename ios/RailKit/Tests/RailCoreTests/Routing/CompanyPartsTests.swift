import Testing

@testable import RailCore

struct CompanyPartsTests {
    @Test func throughServiceCompaniesSplitOnEitherSlash() {
        #expect(RouteGraph.companyParts(company: "JR東日本／東武", country: "jp") == ["JR東日本", "東武"])
        #expect(RouteGraph.companyParts(company: "JR東日本/東武", country: "jp") == ["JR東日本", "東武"])
        #expect(RouteGraph.companyParts(company: " 東急 ／／ 東京メトロ ", country: "jp") == ["東急", "東京メトロ"])
    }
}
