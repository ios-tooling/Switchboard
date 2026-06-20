//
//  SwitchboardClient.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/15/26.
//

import Foundation

/// An object that responds to lifecycle events, state changes, and incoming routes. Register it
/// with ``Switchboard/register(_:)`` and implement only the callbacks you care about — the rest
/// default to no-ops.
///
/// Each callback runs in the client's own isolation — a `@MainActor` client's handlers run on
/// the main actor; an `actor` client's run on its own executor.
public protocol SwitchboardClient: AnyObject, Sendable {
	func onLaunch() async
	func onResume() async
	func onWillEnterForeground() async
	func onBackground() async
	func onTerminate() async
	func onMemoryWarning() async
	func onTick() async
	func onTimeChange() async
	func onStateChange(_ state: SwitchboardState, isActive: Bool) async

	/// Handle an incoming route (notification, universal link, activity, shortcut, …). Return
	/// `true` to claim it and stop routing — clients are offered it in registration order.
	/// Defaults to not handling it.
	func route(_ route: SwitchboardRoute) async -> Bool
}

public extension SwitchboardClient {
	func onLaunch() async { }
	func onResume() async { }
	func onWillEnterForeground() async { }
	func onBackground() async { }
	func onTerminate() async { }
	func onMemoryWarning() async { }
	func onTick() async { }
	func onTimeChange() async { }
	func onStateChange(_ state: SwitchboardState, isActive: Bool) async { }
	func route(_ route: SwitchboardRoute) async -> Bool { false }
}
