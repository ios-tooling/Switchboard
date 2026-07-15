//
//  SwitchboardScheduler.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 7/15/26.
//

import Foundation

/// The pure scheduling core: given a raw event and the current bookkeeping facts, decides
/// what actually gets delivered, what the foreground tick timer should do, and which clients
/// are eligible. Owns no state and touches no platform API — this is the test surface for
/// Switchboard's timing and gating rules; ``Switchboard/dispatch(_:)`` is the impure shell
/// that gathers the facts and applies the plan.
struct SwitchboardScheduler: Sendable {
	enum TimerAction: Sendable { case start, stop, none }

	struct Plan: Equatable, Sendable {
		var events: SwitchboardEvent
		var timerAction: TimerAction
	}

	/// Assembles the events to deliver for one dispatch. Derived events ride their base event:
	/// a version event (`.firstLaunch`/`.launchNewVersion`) rides ahead of `.launch`;
	/// `.resumeDaily` rides a qualifying `.resume` or `.tick`. The tick timer runs
	/// foreground-only: launch/resume start it, background stops it.
	func plan(for events: SwitchboardEvent, versionEvent: SwitchboardEvent? = nil, resumeDailyIsDue: Bool = false) -> Plan {
		var events = events
		if events.contains(.launch), let versionEvent { events.insert(versionEvent) }
		if events.contains(.resume) || events.contains(.tick), resumeDailyIsDue { events.insert(.resumeDaily) }

		var timerAction = TimerAction.none
		if events.contains(.launch) || events.contains(.resume) { timerAction = .start }
		if events.contains(.background) { timerAction = .stop }

		return Plan(events: events, timerAction: timerAction)
	}

	/// Whether a client whose ``SwitchboardClient/requiredStates`` are `requirements` receives
	/// lifecycle events while `active` are the board's active states. State changes, sign-in/out,
	/// and routes are never gated — this applies to ``SwitchboardEvent`` callbacks only.
	func isEligible(requirements: Set<SwitchboardState>, active: Set<SwitchboardState>) -> Bool {
		requirements.isSubset(of: active)
	}
}
