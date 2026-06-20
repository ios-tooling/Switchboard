//
//  Switchboard+Logging.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/19/26.
//

import Foundation
import os

public extension Switchboard {
	/// Enable lightweight `os.Logger` output for debugging. Each time one of `events` fires it's
	/// logged along with the current values of `states`, and a change to any of `states` is
	/// logged too. Call with empty arguments to turn logging off.
	///
	/// ```swift
	/// Switchboard.instance.setLogging(events: .resume, states: [.isSignedIn, .isOnline])
	/// ```
	func setLogging(events: SwitchboardEvent = .all, states: [SwitchboardState] = []) {
		loggedEvents = events
		loggedStates = states
	}

	internal func logEventIfNeeded(_ events: SwitchboardEvent) {
		let fired = events.intersection(loggedEvents)
		guard !fired.isEmpty else { return }

		var line = "▸ \(fired)"
		if !loggedStates.isEmpty {
			let snapshot = loggedStates.map { "\($0.rawValue)=\(has(state: $0))" }.joined(separator: ", ")
			line += "  ·  \(snapshot)"
		}
		print(line)
		Switchboard.logger.log("\(line, privacy: .public)")
	}

	internal func logStateChangeIfNeeded(_ state: SwitchboardState, active: Bool) {
		guard loggedStates.contains(state) else { return }
		Switchboard.logger.log("\("◆ \(state.rawValue) → \(active)", privacy: .public)")
	}

	private static let logger = Logger(subsystem: "Switchboard", category: "lifecycle")
}
