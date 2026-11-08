import Foundation
import Testing

@testable import RailCore

struct TicketParserTests {
    private func lines(_ texts: [String], confidence: Double = 0.9) -> [RecognizedLine] {
        texts.map { RecognizedLine(text: $0, confidence: confidence) }
    }

    // MARK: JP

    @Test func jpShinkansenReservedTicket() {
        let result = TicketParser.parse(
            lines: lines([
                "JR東海", "東京 → 新大阪", "乗車券・新幹線特急券(指定席)", "のぞみ 25号",
                "2026年11月6日(金)", "10:30発 12:55着", "5号車 12番A席", "普通車指定席",
                "¥8,910", "¥5,810", "合計 ¥14,720", "発売日 2026年10月6日", "お問い合わせは駅へ",
            ]),
            region: .jp)
        #expect(result.origin?.value == "東京")
        #expect(result.destination?.value == "新大阪")
        #expect(result.date?.value == TicketDate(year: 2026, month: 11, day: 6))
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.serviceName?.value == "のぞみ")
        #expect(result.serviceNumber?.value == "25")
        #expect(result.car?.value == "5")
        #expect(result.seat?.value == "12A")
        #expect(result.seatClass?.value == "普通車")
        #expect(result.fare?.value == 14720)
        #expect(result.currency?.value == "JPY")
        #expect(result.kind?.value == .seatReservation)
        #expect(result.region == .jp)
    }

    @Test func jpFullWidthDigits() {
        let result = TicketParser.parse(
            lines: lines([
                "東京⇒新大阪", "ひかり　５２１号", "１１月６日", "１０：３０発", "５号車　１２Ａ席",
                "￥１４，７２０",
            ]),
            region: .jp)
        #expect(result.origin?.value == "東京")
        #expect(result.destination?.value == "新大阪")
        #expect(result.serviceName?.value == "ひかり")
        #expect(result.serviceNumber?.value == "521")
        #expect(result.date?.value == TicketDate(year: nil, month: 11, day: 6))
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.car?.value == "5")
        #expect(result.seat?.value == "12A")
        #expect(result.fare?.value == 14720)
    }

    @Test func jpStationsFromSeparateDepartureArrivalLines() {
        let result = TicketParser.parse(
            lines: lines(["東京 10:30発", "新大阪 12:55着", "のぞみ25号", "2026/11/06", "12A", "グリーン車"]),
            region: .jp)
        #expect(result.origin?.value == "東京")
        #expect(result.destination?.value == "新大阪")
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.date?.value == TicketDate(year: 2026, month: 11, day: 6))
        #expect(result.seat?.value == "12A")
        #expect(result.seatClass?.value == "グリーン車")
        #expect(result.serviceNumber?.value == "25")
    }

    @Test func jpIssueDateDoesNotBeatTravelDateAndNoiseIsIgnored() {
        let result = TicketParser.parse(
            lines: lines([
                "2026年10月6日 発売", "|||", "乗車券", "名古屋→京都ゆき", "11月7日 乗車", "有効期間 1日",
                "5番線",
            ]),
            region: .jp)
        #expect(result.date?.value == TicketDate(year: nil, month: 11, day: 7))
        #expect(result.origin?.value == "名古屋")
        #expect(result.destination?.value == "京都")
        #expect(result.kind?.value == .ticket)
        // Platform "5番線" is not a seat.
        #expect(result.seat == nil)
    }

    @Test func jpConfidenceFollowsTheSourceLine() {
        let sure = TicketParser.parse(lines: [RecognizedLine(text: "東京 → 新大阪", confidence: 1)], region: .jp)
        let weak = TicketParser.parse(lines: [RecognizedLine(text: "東京 → 新大阪", confidence: 0.3)], region: .jp)
        #expect((sure.origin?.confidence ?? 0) > (weak.origin?.confidence ?? 1))
        #expect((weak.origin?.confidence ?? 1) <= 0.3)
    }

    @Test func jpEmptyAndGarbage() {
        #expect(TicketParser.parse(lines: [], region: .jp).isEmpty)
        #expect(TicketParser.parse(lines: lines(["", "  ", "~~~", "###"]), region: .jp).isEmpty)
    }

    // MARK: TW

    @Test func twHighSpeedRail() {
        let result = TicketParser.parse(
            lines: lines([
                "台灣高鐵 THSR", "2026/11/06", "台北 Taipei → 左營 Zuoying", "車次 0123",
                "10:30 → 12:15", "5車 12A", "標準車廂", "NT$1,490",
            ]),
            region: .tw)
        #expect(result.origin?.value == "台北")
        #expect(result.destination?.value == "左營")
        #expect(result.date?.value == TicketDate(year: 2026, month: 11, day: 6))
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.serviceNumber?.value == "0123")
        #expect(result.serviceName?.value == "高鐵")
        #expect(result.car?.value == "5")
        #expect(result.seat?.value == "12A")
        #expect(result.seatClass?.value == "標準車廂")
        #expect(result.fare?.value == 149_000)
        #expect(result.currency?.value == "TWD")
        #expect(result.kind?.value == .seatReservation)
    }

    @Test func twTaiwanRailwayWithRepublicEraDate() {
        let result = TicketParser.parse(
            lines: lines([
                "臺灣鐵路 乘車票", "115/11/06", "臺北 至 臺中", "自強 408 次", "開車時間 10:30",
                "車廂 06 座位 21", "票價 NT$375", "有效期限 當日有效",
            ]),
            region: .tw)
        #expect(result.origin?.value == "臺北")
        #expect(result.destination?.value == "臺中")
        #expect(result.date?.value == TicketDate(year: 2026, month: 11, day: 6))
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.serviceName?.value == "自強")
        #expect(result.serviceNumber?.value == "408")
        #expect(result.car?.value == "6")
        #expect(result.seat?.value == "21")
        #expect(result.fare?.value == 37_500)
    }

    @Test func twFullWidthDigits() {
        let result = TicketParser.parse(
            lines: lines(["２０２６年１１月６日", "車次：０１２３", "ＮＴ＄１，４９０"]),
            region: .tw)
        #expect(result.date?.value == TicketDate(year: 2026, month: 11, day: 6))
        #expect(result.serviceNumber?.value == "0123")
        #expect(result.fare?.value == 149_000)
    }

    // MARK: KR

    @Test func krKTX() {
        let result = TicketParser.parse(
            lines: lines([
                "코레일 승차권", "2026.11.06 (금)", "서울 → 부산", "KTX 123", "10:30 → 13:10",
                "5호차 12A", "일반실", "₩59,800", "발매일 2026.10.30",
            ]),
            region: .kr)
        #expect(result.origin?.value == "서울")
        #expect(result.destination?.value == "부산")
        #expect(result.date?.value == TicketDate(year: 2026, month: 11, day: 6))
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.serviceName?.value == "KTX")
        #expect(result.serviceNumber?.value == "123")
        #expect(result.car?.value == "5")
        #expect(result.seat?.value == "12A")
        #expect(result.seatClass?.value == "일반실")
        #expect(result.fare?.value == 59_800)
        #expect(result.currency?.value == "KRW")
        #expect(result.kind?.value == .seatReservation)
    }

    @Test func krLabelsAndHangulDate() {
        let result = TicketParser.parse(
            lines: lines([
                "승차일 2026년 11월 6일", "출발 서울역 10:30", "도착 동대구역", "KTX-산천 401",
                "7호차 좌석 3B", "특실", "￦87,800",
            ]),
            region: .kr)
        #expect(result.origin?.value == "서울")
        #expect(result.destination?.value == "동대구")
        #expect(result.date?.value == TicketDate(year: 2026, month: 11, day: 6))
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.serviceName?.value == "KTX-산천")
        #expect(result.serviceNumber?.value == "401")
        #expect(result.car?.value == "7")
        #expect(result.seat?.value == "3B")
        #expect(result.seatClass?.value == "특실")
        #expect(result.fare?.value == 87_800)
    }

    @Test func krInlineTimesOnRouteLine() {
        let result = TicketParser.parse(
            lines: lines(["서울 10:30 → 부산 13:10", "KTX123", "12호차 5C"]), region: .kr)
        #expect(result.origin?.value == "서울")
        #expect(result.destination?.value == "부산")
        #expect(result.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(result.serviceNumber?.value == "123")
        #expect(result.car?.value == "12")
        #expect(result.seat?.value == "5C")
    }

    // MARK: arrival time

    @Test func jpArrivalIsReadFromTheChakuMarker() {
        let ticket = TicketParser.parse(
            lines: lines(["東京 → 新大阪", "のぞみ 25号", "11月6日", "10:30発 12:55着", "5号車 12番A席"]),
            region: .jp)
        #expect(ticket.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(ticket.arrivalTime?.value == ServiceClockTime(dayOffset: 0, hour: 12, minute: 55))
        let labelled = TicketParser.parse(lines: lines(["東京 10:30発", "新大阪 12:55着"]), region: .jp)
        #expect(labelled.arrivalTime?.value == ServiceClockTime(dayOffset: 0, hour: 12, minute: 55))
        // An issue date or validity line is not an arrival.
        let plain = TicketParser.parse(lines: lines(["名古屋→京都ゆき", "発売日 2026年10月6日 9:12"]), region: .jp)
        #expect(plain.arrivalTime == nil)
    }

    @Test func twArrivalIsReadFromTheRouteOrTheArrivalLabel() {
        let hsr = TicketParser.parse(lines: lines(["台北 → 左營", "10:30 → 12:15"]), region: .tw)
        #expect(hsr.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(hsr.arrivalTime?.value == ServiceClockTime(dayOffset: 0, hour: 12, minute: 15))
        let tra = TicketParser.parse(
            lines: lines(["臺北 至 臺中", "開車時間 10:30", "抵達時間 12:20"]), region: .tw)
        #expect(tra.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 30))
        #expect(tra.arrivalTime?.value == ServiceClockTime(dayOffset: 0, hour: 12, minute: 20))
    }

    @Test func twToMeaningDestinationIsNotAnArrivalMarker() {
        let route = TicketParser.parse(lines: lines(["10:30 到 左營"]), region: .tw)
        #expect(route.arrivalTime == nil)
        let arrived = TicketParser.parse(lines: lines(["12:20抵達"]), region: .tw)
        #expect(arrived.arrivalTime?.value == ServiceClockTime(dayOffset: 0, hour: 12, minute: 20))
    }

    @Test func krArrivalIsReadFromTheDochakMarker() {
        let ticket = TicketParser.parse(
            lines: lines(["서울 → 부산", "KTX 101", "출발 08:00", "도착 10:37"]), region: .kr)
        #expect(ticket.departureTime?.value == ServiceClockTime(dayOffset: 0, hour: 8, minute: 0))
        #expect(ticket.arrivalTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 37))
        let spoken = TicketParser.parse(lines: lines(["10시 37분 도착"]), region: .kr)
        #expect(spoken.arrivalTime?.value == ServiceClockTime(dayOffset: 0, hour: 10, minute: 37))
    }
}
