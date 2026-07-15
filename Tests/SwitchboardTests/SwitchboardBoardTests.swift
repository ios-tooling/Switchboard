//
//  SwitchboardBoardTests.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 7/15/26.
//

import Foundation
import Testing
@testable import Switchboard

@MainActor private final class RecordingClient: SwitchboardClient {
	nonisolated let requirements: Set<SwitchboardState>
	nonisolated let claimsRoutes: Bool
	nonisolated var requiredStates: Set<SwitchboardState> { requirements }

	var launches = 0
	var resumes = 0
	var signIns = 0
	var signOuts = 0
	var routesSeen = 0
	var stateChanges: [(state: SwitchboardState, isActive: Bool)] = []

	nonisolated init(requires: Set<SwitchboardState> = [], claimsRoutes: Bool = false) {
		self.requirements = requires
		self.claimsRoutes = claimsRoutes
	}

	func onLaunch() async { launches += 1 }
	func onResume() async { resumes += 1 }
	func onSignIn() async { signIns += 1 }
	func onSignOut() async { signOuts += 1 }
	func onStateChange(_ state: SwitchboardState, isActive: Bool) async { stateChanges.append((state, isActive)) }
	func route(_ route: SwitchboardRoute) async -> Bool {
		routesSeen += 1
		return claimsRoutes
	}
}

@MainActor private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
	for _ in 0..<200 {
		if condition() { return true }
		try? await Task.sleep(for: .milliseconds(5))
	}
	return condition()
}

// Each test constructs its own board with isolated bookkeeping defaults — no singleton pokes.
@MainActor @Suite(.serialized) struct SwitchboardBoardTests {
	private func makeBoard() -> Switchboard {
		let board = Switchboard()
		board.resumeDailyDefaults = UserDefaults(suiteName: "switchboard.tests.\(UUID().uuidString)")!
		board.launchVersionDefaults = UserDefaults(suiteName: "switchboard.tests.\(UUID().uuidString)")!
		return board
	}

	@Test func stateSetHasClear() {
		let key = SwitchboardState(rawValue: "test.setHasClear")
		let board = makeBoard()
		#expect(!board.has(state: key))
		board.setState(key, active: true)
		#expect(board.has(state: key))
		board.setState(key, active: false)
		#expect(!board.has(state: key))
	}

	@Test func firesLaunchToRegisteredClient() async {
		let board = makeBoard()
		let client = RecordingClient()
		board.register(client)

		board.launched()
		#expect(await eventually { client.launches == 1 })
	}

	@Test func stateChangeFiresOnlyOnRealChange() async {
		let board = makeBoard()
		let client = RecordingClient()
		board.register(client)
		let key = SwitchboardState(rawValue: "test.onlyOnChange")

		board.setState(key, active: true)
		#expect(await eventually { client.stateChanges.count == 1 })
		#expect(client.stateChanges.last?.state == key)
		#expect(client.stateChanges.last?.isActive == true)

		board.setState(key, active: true)   // no-op: already present, must not fire again
		try? await Task.sleep(for: .milliseconds(50))
		#expect(client.stateChanges.count == 1)
	}

	@Test func gatedClientSkipsLifecycleEventsWhileIneligible() async {
		let board = makeBoard()
		let gated = RecordingClient(requires: [.isSignedIn])
		let ungated = RecordingClient()
		board.register(gated)
		board.register(ungated)

		board.launched()
		#expect(await eventually { ungated.launches == 1 })
		#expect(gated.launches == 0)

		board.dispatch(.resume)
		#expect(await eventually { ungated.resumes == 1 })
		#expect(gated.resumes == 0)
	}

	@Test func gatedClientReceivesLifecycleEventsOnceEligible() async {
		let board = makeBoard()
		let gated = RecordingClient(requires: [.isSignedIn])
		board.register(gated)
		board.setState(.isSignedIn, active: true)

		board.launched()
		#expect(await eventually { gated.launches == 1 })

		board.dispatch(.resume)
		#expect(await eventually { gated.resumes == 1 })
	}

	@Test func gatedClientAlwaysHearsSignInAndSignOut() async {
		let board = makeBoard()
		let gated = RecordingClient(requires: [.isSignedIn])
		board.register(gated)

		// Both transitions arrive even though the client is lifecycle-ineligible before
		// sign-in and after sign-out — that's how it warms up and tears down.
		board.setState(.isSignedIn, active: true)
		#expect(await eventually { gated.signIns == 1 })

		board.setState(.isSignedIn, active: false)
		#expect(await eventually { gated.signOuts == 1 })
		#expect(gated.stateChanges.count == 2)
	}

	@Test func gatedClientIsStillOfferedRoutes() async {
		let board = makeBoard()
		let gated = RecordingClient(requires: [.isSignedIn], claimsRoutes: true)
		board.register(gated)
		board.launched()

		let claimed = await board.route(.universalLink(URL(string: "https://example.com/mood")!))
		#expect(claimed)
		#expect(gated.routesSeen == 1)
	}

	@Test func userIntentRouteBuffersUntilLaunched() async {
		let board = makeBoard()
		let claimer = RecordingClient(claimsRoutes: true)
		board.register(claimer)

		let buffered = await board.route(.universalLink(URL(string: "https://example.com/mood")!))
		#expect(!buffered)		// not yet launched: buffered, reported unhandled
		#expect(claimer.routesSeen == 0)

		board.launched()
		#expect(await eventually { claimer.routesSeen == 1 })
	}

	@Test func launchVersionBookkeeping() {
		let board = makeBoard()
		#expect(board.launchVersionEventAndMark(currentVersion: "1.0") == .firstLaunch)
		#expect(board.launchVersionEventAndMark(currentVersion: "1.0") == nil)
		#expect(board.launchVersionEventAndMark(currentVersion: "1.1") == .launchNewVersion)
		#expect(board.launchVersionEventAndMark(currentVersion: nil) == nil)
	}

	@Test func resumeDailyBookkeeping() {
		let board = makeBoard()
		let now = Date()
		#expect(board.shouldFireResumeDailyAndMark(now: now))
		#expect(!board.shouldFireResumeDailyAndMark(now: now))		// already fired today

		let board2 = makeBoard()
		board2.resumeDailyAfterHour = 24		// unreachable hour: held all day, unmarked
		#expect(!board2.shouldFireResumeDailyAndMark(now: now))
		board2.resumeDailyAfterHour = 0
		#expect(board2.shouldFireResumeDailyAndMark(now: now))		// still fires once the hour passes
	}
}
