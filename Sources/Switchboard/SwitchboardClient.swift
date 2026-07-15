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
	/// States that must all be active for this client to receive lifecycle events
	/// (``onLaunch()``, ``onResume()``, ``onTick()``, ``onTimeChange()``, …). State changes —
	/// ``onStateChange(_:isActive:)``, ``onSignIn()``, ``onSignOut()`` — and ``route(_:)``
	/// are always delivered regardless. Defaults to empty (no gating). Declare
	/// `[.isSignedIn]` on a client whose lifecycle work only makes sense signed in,
	/// instead of guarding inside each handler.
	nonisolated var requiredStates: Set<SwitchboardState> { get }

	func onLaunch() async

	/// Fired just before ``onLaunch()`` the very first time the app launches on this device.
	func onFirstLaunch() async
	/// Fired just before ``onLaunch()`` on the first launch after the app's version string changed.
	func onLaunchNewVersion() async
	func onResume() async

	/// Fired at most once per local calendar day — on the first qualifying resume (or the
	/// foreground tick that crosses the boundary). Held until ``Switchboard/resumeDailyAfterHour``
	/// (if set) has passed.
	func onResumeDaily() async
	func onWillEnterForeground() async
	func onBackground() async
	func onTerminate() async
	func onMemoryWarning() async
	func onTick() async
	func onTimeChange() async
	func onStateChange(_ state: SwitchboardState, isActive: Bool) async

	/// Fired when `.isSignedIn` becomes active — a convenience layered on
	/// `onStateChange(.isSignedIn, isActive: true)`, delivered just after it.
	func onSignIn() async
	/// Fired when `.isSignedIn` becomes inactive — a convenience layered on
	/// `onStateChange(.isSignedIn, isActive: false)`, delivered just after it.
	func onSignOut() async

	/// Handle an incoming route (notification, universal link, activity, shortcut, …). Return
	/// `true` to claim it and stop routing — clients are offered it in registration order.
	/// Defaults to not handling it.
	func route(_ route: SwitchboardRoute) async -> Bool
}

public extension SwitchboardClient {
	nonisolated var requiredStates: Set<SwitchboardState> { [] }

	func onLaunch() async { }
	func onFirstLaunch() async { }
	func onLaunchNewVersion() async { }
	func onResume() async { }
	func onResumeDaily() async { }
	func onWillEnterForeground() async { }
	func onBackground() async { }
	func onTerminate() async { }
	func onMemoryWarning() async { }
	func onTick() async { }
	func onTimeChange() async { }
	func onStateChange(_ state: SwitchboardState, isActive: Bool) async { }
	func onSignIn() async { }
	func onSignOut() async { }
	func route(_ route: SwitchboardRoute) async -> Bool { false }
}
