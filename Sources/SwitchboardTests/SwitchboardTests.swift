import Testing
import Foundation
@testable import Switchboard

@MainActor private final class RecordingClient: SwitchboardClient {
	var launches = 0
	var ticks = 0
	var stateChanges: [(state: SwitchboardState, isActive: Bool)] = []

	func onLaunch() async { launches += 1 }
	func onTick() async { ticks += 1 }
	func onStateChange(_ state: SwitchboardState, isActive: Bool) async { stateChanges.append((state, isActive)) }
}

@MainActor private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
	for _ in 0..<200 {
		if condition() { return true }
		try? await Task.sleep(for: .milliseconds(5))
	}
	return condition()
}

// Switchboard is a process-global singleton, so the suite is serialized and each test uses a
// unique state key and cancels its registration.
@MainActor @Suite(.serialized) struct SwitchboardTests {
	@Test func stateSetHasClear() {
		let key = SwitchboardState(rawValue: "test.setHasClear")
		let board = Switchboard.instance
		board.setState(key, active: false)
		#expect(!board.has(state: key))
		board.setState(key, active: true)
		#expect(board.has(state: key))
		board.setState(key, active: false)
		#expect(!board.has(state: key))
	}

	@Test func firesLaunchToRegisteredClient() async {
		let client = RecordingClient()
		let registration = Switchboard.instance.register(client)
		defer { registration.cancel() }

		Switchboard.instance.launched()
		#expect(await eventually { client.launches == 1 })
	}

	/// Point the board's resume-daily store at a scratch suite for the duration of a test, and
	/// restore its `resumeDailyAfterHour`.
	private func withScratchBoard(_ suiteName: String, _ body: (Switchboard) -> Void) {
		let board = Switchboard.instance
		let previousDefaults = board.resumeDailyDefaults
		let previousHour = board.resumeDailyAfterHour
		let suite = UserDefaults(suiteName: suiteName)!
		suite.removePersistentDomain(forName: suiteName)
		board.resumeDailyDefaults = suite
		defer {
			board.resumeDailyDefaults = previousDefaults
			board.resumeDailyAfterHour = previousHour
			suite.removePersistentDomain(forName: suiteName)
		}
		body(board)
	}

	@Test func resumeDailyFiresOncePerDay() {
		withScratchBoard("switchboard.test.oncePerDay") { board in
			board.resumeDailyAfterHour = nil
			#expect(board.shouldFireResumeDailyAndMark())    // first → fires
			#expect(!board.shouldFireResumeDailyAndMark())   // same day → suppressed

			board.resumeDailyDefaults.set(Calendar.current.date(byAdding: .day, value: -1, to: Date()),
			                              forKey: Switchboard.lastResumeDailyKey)
			#expect(board.shouldFireResumeDailyAndMark())    // yesterday → fires again
		}
	}

	@Test func resumeDailyAfterHourHoldsUntilHourWithoutMarking() {
		withScratchBoard("switchboard.test.afterHour") { board in
			board.resumeDailyAfterHour = 8
			let cal = Calendar.current
			let midnight = cal.startOfDay(for: Date())
			let at7 = cal.date(byAdding: .hour, value: 7, to: midnight)!
			let at9 = cal.date(byAdding: .hour, value: 9, to: midnight)!

			#expect(!board.shouldFireResumeDailyAndMark(now: at7))  // before 8 → no fire, no mark
			#expect(board.shouldFireResumeDailyAndMark(now: at9))   // at/after 8 → fires, marks
			#expect(!board.shouldFireResumeDailyAndMark(now: at9))  // already fired today → suppressed
		}
	}

	@Test func stateChangeFiresOnlyOnRealChange() async {
		let client = RecordingClient()
		let registration = Switchboard.instance.register(client)
		let key = SwitchboardState(rawValue: "test.onlyOnChange")
		let board = Switchboard.instance
		board.setState(key, active: false)
		defer { registration.cancel(); board.setState(key, active: false) }

		let baseline = client.stateChanges.count
		board.setState(key, active: true)
		#expect(await eventually { client.stateChanges.count == baseline + 1 })
		#expect(client.stateChanges.last?.state == key)
		#expect(client.stateChanges.last?.isActive == true)

		board.setState(key, active: true)   // no-op: already present, must not fire again
		try? await Task.sleep(for: .milliseconds(50))
		#expect(client.stateChanges.count == baseline + 1)
	}
}
