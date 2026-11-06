import Testing
import UIKit
@testable import RailMap

@MainActor
struct PresentationHostTests {
    @Test func requestsInDifferentWindowsDoNotCancelEachOther() async throws {
        let firstWindow = UIWindow()
        firstWindow.rootViewController = UIViewController()
        let secondWindow = UIWindow()
        secondWindow.rootViewController = UIViewController()
        let first = PresentationHost()
        let second = PresentationHost()
        first.attach(to: firstWindow)
        second.attach(to: secondWindow)
        var delivered: [String] = []
        first.afterTeardown { delivered.append("obsolete") }
        first.afterTeardown { delivered.append("first") }
        second.afterTeardown { delivered.append("second") }
        try await Task.sleep(for: .milliseconds(500))
        #expect(Set(delivered) == ["first", "second"])
        #expect(delivered.count == 2)
    }

    @Test func removedHostDoesNotDeliverItsOldRequestIntoAnotherWindow() async throws {
        let window = UIWindow()
        window.rootViewController = UIViewController()
        let host = PresentationHost()
        host.attach(to: window)
        var delivered = false
        host.afterTeardown { delivered = true }
        host.attach(to: nil)
        host.attach(to: window)
        try await Task.sleep(for: .milliseconds(450))
        #expect(!delivered)
    }
}
