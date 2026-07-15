//
//  Switchboard.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 12/14/25.
//

import Foundation

#if os(iOS) || os(tvOS) || os(visionOS)
	import UIKit
#endif

/// The central lifecycle coordinator. Register a ``SwitchboardClient`` and it receives the
/// lifecycle callbacks it implements; everything else defaults to a no-op.
///
/// ```swift
/// Switchboard.instance.register(myStore)
/// ```
///
/// `.resume`/`.background`/`.terminate` are driven by platform notifications; a significant
/// time change (e.g. midnight rollover) fires `.timeChange`; `.tick` fires on a 15-minute
/// timer while foregrounded; `.launch` is fired explicitly via ``launched()`` once clients are
/// registered. State changes (see ``setState(_:active:)``) are delivered via
/// ``SwitchboardClient/onStateChange(_:isActive:)``.
///
/// Clients are notified sequentially, in registration order. Handlers are `async` and run in
/// each client's own isolation; a client is held weakly, so a deallocated client is skipped.
@MainActor public final class Switchboard {
	public static let instance = Switchboard()

	/// A token for a single ``register(_:)`` call. Call ``cancel()`` to stop observing.
	@MainActor public final class Registration {
		fileprivate weak var board: Switchboard?
		public func cancel() { board?.cancel(self) }
	}

	private final class Entry {
		let registration: Registration
		let name: String
		weak var client: SwitchboardClient?

		init(registration: Registration, name: String, client: SwitchboardClient) {
			self.registration = registration
			self.name = name
			self.client = client
		}
	}

	private var entries: [Entry] = []
	private var observingSystemEvents = false
	// Route buffering (see `route(_:)`); internal so tests can reset between runs.
	var hasLaunched = false
	var pendingRoutes: [SwitchboardRoute] = []
	private static let pendingRouteLimit = 8
	var tokens: [any NSObjectProtocol] = []
	private var states: Set<SwitchboardState> = []
	private var tickTask: Task<Void, Never>?
	// Retains the opt-in `UNUserNotificationCenter` delegate adapter (the system holds it weakly).
	var notificationDelegate: AnyObject?
	// System-state observation (see Switchboard+SystemStates): the reachability monitor + a guard.
	var systemStatesObserved = false
	var pathMonitor: AnyObject?
	// Optional debug logging config (see Switchboard+Logging).
	var loggedEvents: SwitchboardEvent = []
	var loggedStates: [SwitchboardState] = []
	/// If set, `.resumeDaily` is held until the local hour reaches it (e.g. `8` → not before
	/// 8am). Before then it doesn't fire and doesn't count as the day's resume, so a later
	/// resume — or the foreground tick once the hour passes — still delivers it that day.
	/// `nil` (the default) fires on the first resume of each local day.
	public var resumeDailyAfterHour: Int?
	// Backing store for `.resumeDaily` bookkeeping; overridable in tests.
	var resumeDailyDefaults: UserDefaults = .standard
	// Backing store for `.firstLaunch`/`.launchNewVersion` bookkeeping; overridable in tests.
	var launchVersionDefaults: UserDefaults = .standard

	private static let tickInterval: TimeInterval = 15 * 60
	// The pure scheduling core — event assembly, timer fate, and gating decisions live there.
	let scheduler = SwitchboardScheduler()

	// Apps use `instance`; the internal initializer exists so package tests can construct
	// isolated boards (inject fresh `resumeDailyDefaults`/`launchVersionDefaults` in tests).
	init() { }

	// MARK: - State

	/// Add or remove `state`. If the set actually changes, every registered client is notified
	/// via ``SwitchboardClient/onStateChange(_:isActive:)``.
	public func setState(_ state: SwitchboardState, active: Bool) {
		let changed = active ? states.insert(state).inserted : (states.remove(state) != nil)
		guard changed else { return }
		logStateChangeIfNeeded(state, active: active)

		let clients = entries.compactMap(\.client)
		guard !clients.isEmpty else { return }
		Task {
			for client in clients { await Switchboard.deliver(state, active: active, to: client) }
		}
	}

	public func has(state: SwitchboardState) -> Bool { states.contains(state) }

	// MARK: - Registration

	/// Register `client` for lifecycle and state callbacks. The client's type name is recorded
	/// for debugging. Returns a token you can ``Registration/cancel()`` later.
	@discardableResult
	public func register(_ client: SwitchboardClient) -> Registration {
		let registration = Registration()
		registration.board = self
		entries.append(Entry(registration: registration, name: String(describing: type(of: client)), client: client))
		startObservingSystemEvents()
		return registration
	}

	/// Fire `.launch` to all registered clients, in registration order. Call once at app launch,
	/// after clients are registered. A device's first-ever launch is preceded by `.firstLaunch`;
	/// the first launch after the app's version string changes, by `.launchNewVersion`.
	/// Any user-intent routes that arrived earlier are replayed, in order, once launch dispatch
	/// begins (route execution may interleave with launch handlers — claimers should tolerate
	/// warming state).
	public func launched() {
		hasLaunched = true
		dispatch(.launch)
		replayPendingRoutes()
	}

	/// Route an incoming notification to registered clients, in registration order, until one
	/// claims it (returns `true`). Returns whether any client handled it.
	///
	/// A user-intent route (a tap, link, activity — see ``SwitchboardRoute/Origin/isUserIntent``)
	/// arriving before ``launched()`` is buffered and replayed once launch happens, so cold-start
	/// deep links don't race client registration; buffered routes return `false` here. Silent
	/// notification routes are never buffered — they dispatch to whoever is registered right now.
	///
	/// Forward notifications here from your `UNUserNotificationCenterDelegate` / app delegate —
	/// or opt Switchboard in as the notification-center delegate with
	/// ``useAsNotificationDelegate(foregroundPresentation:)``.
	@discardableResult
	public func route(_ route: SwitchboardRoute) async -> Bool {
		if !hasLaunched, route.isUserIntent {
			pendingRoutes.append(route)
			if pendingRoutes.count > Self.pendingRouteLimit { pendingRoutes.removeFirst(pendingRoutes.count - Self.pendingRouteLimit) }
			return false
		}
		for client in entries.compactMap(\.client) {
			if await client.route(route) { return true }
		}
		return false
	}

	private func replayPendingRoutes() {
		guard !pendingRoutes.isEmpty else { return }
		let pending = pendingRoutes
		pendingRoutes = []
		Task {
			for route in pending { await self.route(route) }
		}
	}

	/// Stop notifying the client associated with `registration`.
	public func cancel(_ registration: Registration) {
		entries.removeAll { $0.registration === registration }
	}

	// MARK: - Private

	private func startObservingSystemEvents() {
		guard !observingSystemEvents else { return }
		observingSystemEvents = true

		for (event, name) in SwitchboardEvent.notificationMappings {
			let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.dispatch(event) }
			}
			tokens.append(token)
		}

		#if os(iOS) || os(tvOS) || os(visionOS)
			// A significant time change (midnight, timezone shift) fires `.timeChange`.
			let token = NotificationCenter.default.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.dispatch(.timeChange) }
			}
			tokens.append(token)
		#endif
	}

	// The impure shell: gathers the bookkeeping facts (marking them as a side effect), asks the
	// scheduler for a plan, applies the timer action, and delivers to eligible clients. Internal
	// so package tests can drive lifecycle events on constructed boards.
	func dispatch(_ events: SwitchboardEvent) {
		// The `…AndMark` helpers record bookkeeping, so consult them only when their base
		// event is present — the scheduler re-applies the riding rules on the pure side.
		let versionEvent = events.contains(.launch) ? launchVersionEventAndMark() : nil
		let resumeDailyIsDue = (events.contains(.resume) || events.contains(.tick)) ? shouldFireResumeDailyAndMark() : false
		let plan = scheduler.plan(for: events, versionEvent: versionEvent, resumeDailyIsDue: resumeDailyIsDue)
		logEventIfNeeded(plan.events)

		switch plan.timerAction {
		case .start: startTimer()
		case .stop: stopTimer()
		case .none: break
		}

		let clients = entries.compactMap(\.client).filter { scheduler.isEligible(requirements: $0.requiredStates, active: states) }
		guard !clients.isEmpty else { return }
		Task {
			for client in clients { await Switchboard.deliver(plan.events, to: client) }
		}
	}

	private static func deliver(_ events: SwitchboardEvent, to client: SwitchboardClient) async {
		if events.contains(.firstLaunch) { await client.onFirstLaunch() }
		if events.contains(.launchNewVersion) { await client.onLaunchNewVersion() }
		if events.contains(.launch) { await client.onLaunch() }
		if events.contains(.resume) { await client.onResume() }
		if events.contains(.resumeDaily) { await client.onResumeDaily() }
		if events.contains(.willEnterForeground) { await client.onWillEnterForeground() }
		if events.contains(.background) { await client.onBackground() }
		if events.contains(.terminate) { await client.onTerminate() }
		if events.contains(.memoryWarning) { await client.onMemoryWarning() }
		if events.contains(.tick) { await client.onTick() }
		if events.contains(.timeChange) { await client.onTimeChange() }
	}

	private static func deliver(_ state: SwitchboardState, active: Bool, to client: SwitchboardClient) async {
		await client.onStateChange(state, isActive: active)
		if state == .isSignedIn {
			if active { await client.onSignIn() } else { await client.onSignOut() }
		}
	}

	// MARK: - Tick timer (foreground only)

	private func startTimer() {
		guard tickTask == nil else { return }
		tickTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(Switchboard.tickInterval))
				if Task.isCancelled { return }
				self?.dispatch(.tick)
			}
		}
	}

	private func stopTimer() {
		tickTask?.cancel()
		tickTask = nil
	}
}
