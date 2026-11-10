import AppKit
import XCTest
@testable import Search

/// ⌘Q's card (QuitPrompt): on by default, Return and a second ⌘Q quit,
/// Escape stays, and "Quit, and don't ask again" turns it off for good.
@MainActor
final class QuitConfirmationTests: XCTestCase {
    private var previous: Any?

    override class func setUp() {
        setenv("SEARCH_PROBE", "quit-confirmation-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        previous = Store.settings.object(forKey: Preferences.confirmQuitKey)
        Store.settings.set(true, forKey: Preferences.confirmQuitKey)
    }

    override func tearDown() async throws {
        Store.settings.set(previous, forKey: Preferences.confirmQuitKey)
    }

    func testOnByDefaultAndPreferencePersists() {
        Store.settings.removeObject(forKey: Preferences.confirmQuitKey)
        XCTAssertTrue(Preferences().confirmsQuit)
        XCTAssertTrue(Preferences.confirmsQuitStored)
        let prefs = Preferences()
        prefs.confirmsQuit = false
        XCTAssertFalse(Preferences().confirmsQuit)
        // Off: nothing asks.
        XCTAssertTrue(Links.shouldQuit())
        XCTAssertNil(NSApp.modalWindow)
    }

    func testReturnQuits() {
        XCTAssertTrue(answer { self.key(36) })
    }

    func testEscapeStaysAndCanAskAgain() {
        XCTAssertFalse(answer { self.key(53, "\u{1b}") })
        XCTAssertTrue(answer { self.key(36) })
    }

    func testCommandQAgainQuits() {
        XCTAssertTrue(answer { self.key(12, "q", [.command]) })
    }

    func testRepeatedQuitDoesNotOpenAnotherQuestion() {
        XCTAssertFalse(answer {
            let window = NSApp.modalWindow
            XCTAssertFalse(Links.shouldQuit())
            XCTAssertTrue(NSApp.modalWindow === window)
            self.key(53, "\u{1b}")
        })
    }

    func testQuitForGoodTurnsTheQuestionOff() {
        XCTAssertTrue(Links.take(.quitForGood))
        XCTAssertFalse(Preferences.confirmsQuitStored)
        XCTAssertTrue(Links.take(.quit))
        XCTAssertFalse(Links.take(.stay))
    }

    private func key(_ code: UInt16, _ characters: String = "\r", _ flags: NSEvent.ModifierFlags = []) {
        guard let window = NSApp.modalWindow else { return XCTFail("No quit card") }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: code)!
        NSApp.sendEvent(event)
    }

    private func answer(whileAsking: @escaping () -> Void) -> Bool {
        var answered = false
        let fallback = Timer(timeInterval: 2, repeats: false) { _ in
            MainActor.assumeIsolated {
                if !answered { NSApp.stopModal(withCode: .abort) }
            }
        }
        RunLoop.main.add(fallback, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard NSApp.modalWindow != nil else { return XCTFail("No quit card") }
            whileAsking()
        }
        let result = Links.shouldQuit()
        answered = true
        XCTAssertTrue(fallback.isValid, "A key must answer the card")
        fallback.invalidate()
        return result
    }
}
