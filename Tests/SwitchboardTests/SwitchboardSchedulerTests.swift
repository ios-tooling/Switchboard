//
//  SwitchboardSchedulerTests.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 7/15/26.
//

import Testing
@testable import Switchboard

// The pure core: timing and gating rules with no board, no platform, no state.
struct SwitchboardSchedulerTests {
	let scheduler = SwitchboardScheduler()

	@Test func launchRidesVersionEventAndStartsTimer() {
		let plan = scheduler.plan(for: .launch, versionEvent: .firstLaunch)
		#expect(plan.events.contains(.firstLaunch))
		#expect(plan.events.contains(.launch))
		#expect(plan.timerAction == .start)
	}

	@Test func launchWithoutVersionEventDeliversLaunchOnly() {
		let plan = scheduler.plan(for: .launch)
		#expect(plan.events == .launch)
		#expect(plan.timerAction == .start)
	}

	@Test func versionEventIgnoredWithoutLaunch() {
		let plan = scheduler.plan(for: .resume, versionEvent: .launchNewVersion)
		#expect(!plan.events.contains(.launchNewVersion))
	}

	@Test func resumeRidesResumeDailyWhenDue() {
		let plan = scheduler.plan(for: .resume, resumeDailyIsDue: true)
		#expect(plan.events.contains(.resumeDaily))
		#expect(plan.timerAction == .start)
	}

	@Test func resumeSkipsResumeDailyWhenNotDue() {
		let plan = scheduler.plan(for: .resume, resumeDailyIsDue: false)
		#expect(!plan.events.contains(.resumeDaily))
	}

	@Test func tickRidesResumeDailyButLeavesTimerAlone() {
		let plan = scheduler.plan(for: .tick, resumeDailyIsDue: true)
		#expect(plan.events.contains(.resumeDaily))
		#expect(plan.timerAction == .none)
	}

	@Test func resumeDailyNeverRidesOtherEvents() {
		let plan = scheduler.plan(for: .timeChange, resumeDailyIsDue: true)
		#expect(!plan.events.contains(.resumeDaily))
	}

	@Test func backgroundStopsTimer() {
		#expect(scheduler.plan(for: .background).timerAction == .stop)
	}

	@Test func timeChangeLeavesTimerAlone() {
		#expect(scheduler.plan(for: .timeChange).timerAction == .none)
	}

	@Test func noRequirementsIsAlwaysEligible() {
		#expect(scheduler.isEligible(requirements: [], active: []))
		#expect(scheduler.isEligible(requirements: [], active: [.isSignedIn]))
	}

	@Test func missingRequiredStateBlocksDelivery() {
		#expect(!scheduler.isEligible(requirements: [.isSignedIn], active: []))
		#expect(!scheduler.isEligible(requirements: [.isSignedIn, .isOnline], active: [.isOnline]))
	}

	@Test func activeRequiredStatesAllowDelivery() {
		#expect(scheduler.isEligible(requirements: [.isSignedIn], active: [.isSignedIn]))
		#expect(scheduler.isEligible(requirements: [.isSignedIn, .isOnline], active: [.isSignedIn, .isOnline, .lowPowerMode]))
	}
}
