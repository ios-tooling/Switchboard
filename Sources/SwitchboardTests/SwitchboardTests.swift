import Testing
import Foundation
@testable import Switchboard

@MainActor private final class RecordingClient: SwitchboardClient {
	var launches = 0
	var ticks = 0
	var signIns = 0
	var signOuts = 0
	var stateChanges: [(state: SwitchboardState, isActive: Bool)] = []

	func onLaunch() async { launches += 1 }
	func onTick() async { ticks += 1 }
	func onSignIn() async { signIns += 1 }
	func onSignOut() async { signOuts += 1 }
	func onStateChange(_ state: SwitchboardState, isActive: Bool) async { stateChanges.append((state, isActive)) }
}


@MainActor private final class RoutingClient: SwitchboardClient {
	var routedURLs: [URL?] = []
	func route(_ route: SwitchboardRoute) async -> Bool {
		routedURLs.append(route.url)
		return true
	}
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

	/// Point the board's resume-daily and launch-version stores at a scratch suite for the
	/// duration of a test, and restore its `resumeDailyAfterHour`.
	private func withScratchBoard(_ suiteName: String, _ body: (Switchboard) -> Void) {
		let board = Switchboard.instance
		let previousDefaults = board.resumeDailyDefaults
		let previousLaunchDefaults = board.launchVersionDefaults
		let previousHour = board.resumeDailyAfterHour
		let suite = UserDefaults(suiteName: suiteName)!
		suite.removePersistentDomain(forName: suiteName)
		board.resumeDailyDefaults = suite
		board.launchVersionDefaults = suite
		defer {
			board.resumeDailyDefaults = previousDefaults
			board.launchVersionDefaults = previousLaunchDefaults
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

	@Test func firstLaunchFiresWhenNoVersionStored() {
		withScratchBoard("switchboard.test.firstLaunch") { board in
			#expect(board.launchVersionEventAndMark(currentVersion: "1.0") == .firstLaunch)
			#expect(board.launchVersionEventAndMark(currentVersion: "1.0") == nil)   // recorded → unchanged
		}
	}

	@Test func launchNewVersionFiresWhenVersionChanges() {
		withScratchBoard("switchboard.test.newVersion") { board in
			#expect(board.launchVersionEventAndMark(currentVersion: "1.0") == .firstLaunch)       // records 1.0
			#expect(board.launchVersionEventAndMark(currentVersion: "1.1") == .launchNewVersion)  // changed
			#expect(board.launchVersionEventAndMark(currentVersion: "1.1") == nil)                // unchanged again
		}
	}

	@Test func launchVersionDoesNotFireWithoutAVersion() {
		withScratchBoard("switchboard.test.noVersion") { board in
			#expect(board.launchVersionEventAndMark(currentVersion: nil) == nil)
			#expect(board.launchVersionEventAndMark(currentVersion: "1.0") == .firstLaunch)  // nothing was recorded
		}
	}

	@Test func signInOutCallbacksTrackSignedInState() async {
		let client = RecordingClient()
		let board = Switchboard.instance
		board.setState(.isSignedIn, active: false)   // known baseline, before registering
		let registration = board.register(client)
		defer { registration.cancel(); board.setState(.isSignedIn, active: false) }

		board.setState(.isSignedIn, active: true)
		#expect(await eventually { client.signIns == 1 })
		#expect(client.signOuts == 0)

		board.setState(.isSignedIn, active: false)
		#expect(await eventually { client.signOuts == 1 })
		#expect(client.signIns == 1)
	}

	@Test func signInOutIgnoreOtherStates() async {
		let client = RecordingClient()
		let board = Switchboard.instance
		let key = SwitchboardState(rawValue: "test.notSignedIn")
		board.setState(key, active: false)
		let registration = board.register(client)
		defer { registration.cancel(); board.setState(key, active: false) }

		board.setState(key, active: true)
		#expect(await eventually { client.stateChanges.contains { $0.state == key && $0.isActive } })
		#expect(client.signIns == 0)
		#expect(client.signOuts == 0)
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

	/// Run `body` with the board in a pre-launch state, restoring launch state afterward.
	private func withUnlaunchedBoard(_ body: (Switchboard) async -> Void) async {
		let board = Switchboard.instance
		let wasLaunched = board.hasLaunched
		board.hasLaunched = false
		await body(board)
		board.pendingRoutes = []
		board.hasLaunched = wasLaunched
	}

	@Test func buffersUserIntentRoutesUntilLaunched() async {
		await withUnlaunchedBoard { board in
			let client = RoutingClient()
			let registration = board.register(client)
			defer { registration.cancel() }

			let first = URL(string: "test://feed/item/1")!
			let second = URL(string: "test://mood")!
			#expect(await board.route(.urlScheme(first)) == false)
			#expect(await board.route(.urlScheme(second)) == false)
			#expect(client.routedURLs.isEmpty)

			board.launched()
			#expect(await eventually { client.routedURLs.count == 2 })
			#expect(client.routedURLs == [first, second])
		}
	}

	@Test func silentNotificationsAreNeverBuffered() async {
		await withUnlaunchedBoard { board in
			let client = RoutingClient()
			let registration = board.register(client)
			defer { registration.cancel() }

			// dispatches immediately to registered clients, even before launch
			let handled = await board.route(.notification(["aps": ["data": ["url": "test://silent"]]], source: .background))
			#expect(handled)
			#expect(client.routedURLs.count == 1)
			#expect(board.pendingRoutes.isEmpty)
		}
	}

	@Test func routesDispatchImmediatelyAfterLaunch() async {
		let board = Switchboard.instance
		let wasLaunched = board.hasLaunched
		board.hasLaunched = true
		defer { board.hasLaunched = wasLaunched }

		let client = RoutingClient()
		let registration = board.register(client)
		defer { registration.cancel() }

		let url = URL(string: "test://immediate")!
		#expect(await board.route(.universalLink(url)))
		#expect(client.routedURLs == [url])
	}
}
