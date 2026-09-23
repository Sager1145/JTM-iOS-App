import Testing

@testable import RailPresentation

struct JourneyHeroIdentityTests {

    @Test
    func choosingAnotherJourneyIsAnotherCard() {
        let first = JourneyHeroIdentity.resolve(selectedTrainID: "a", transportOnScreen: false)
        let second = JourneyHeroIdentity.resolve(selectedTrainID: "b", transportOnScreen: false)
        #expect(first == .journey("a"))
        #expect(first != second)
    }

    @Test
    func reselectingTheSameJourneyIsTheSameCard() {
        let before = JourneyHeroIdentity.resolve(selectedTrainID: "a", transportOnScreen: false)
        let after = JourneyHeroIdentity.resolve(selectedTrainID: "a", transportOnScreen: false)
        #expect(before == after)
    }

    @Test
    func aRunKeepsOneCardAcrossItsHandOffs() {
        let first = JourneyHeroIdentity.resolve(selectedTrainID: "a", transportOnScreen: true)
        let handedOn = JourneyHeroIdentity.resolve(selectedTrainID: "b", transportOnScreen: true)
        #expect(first == .run)
        #expect(first == handedOn)
    }

    @Test
    func aRunTakingOverAndGivingBackAreBothNewCards() {
        let chosen = JourneyHeroIdentity.resolve(selectedTrainID: "a", transportOnScreen: false)
        let running = JourneyHeroIdentity.resolve(selectedTrainID: "a", transportOnScreen: true)
        let restored = JourneyHeroIdentity.resolve(selectedTrainID: "a", transportOnScreen: false)
        #expect(chosen != running)
        #expect(running != restored)
        #expect(chosen == restored)
    }
}
