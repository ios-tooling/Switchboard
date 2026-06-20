//
//  Switchboard+SystemStates.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/19/26.
//

import Foundation

#if canImport(Network)
	import Network
#endif

#if os(iOS) || os(tvOS) || os(visionOS)
	import UIKit
#endif

public extension Switchboard {
	/// Reflect device conditions into the state set: ``SwitchboardState/lowPowerMode``,
	/// ``SwitchboardState/thermalPressure``, ``SwitchboardState/protectedDataAvailable``, and
	/// ``SwitchboardState/isOnline``. Idempotent; call once at launch (before registering
	/// clients, so the seeded values are visible to their `onLaunch`).
	///
	/// All states are seeded synchronously except `.isOnline`, whose reachability monitor
	/// delivers its first value shortly after start.
	func observeSystemStates() {
		guard !systemStatesObserved else { return }
		systemStatesObserved = true

		updatePowerState()
		tokens.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in self?.updatePowerState() }
		})

		updateThermalState()
		tokens.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in self?.updateThermalState() }
		})

		#if os(iOS) || os(tvOS) || os(visionOS)
			setState(.protectedDataAvailable, active: UIApplication.shared.isProtectedDataAvailable)
			tokens.append(NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.setState(.protectedDataAvailable, active: true) }
			})
			tokens.append(NotificationCenter.default.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.setState(.protectedDataAvailable, active: false) }
			})
		#endif

		startReachabilityMonitor()
	}

	private func updatePowerState() {
		setState(.lowPowerMode, active: ProcessInfo.processInfo.isLowPowerModeEnabled)
	}

	private func updateThermalState() {
		let thermal = ProcessInfo.processInfo.thermalState
		setState(.thermalPressure, active: thermal == .serious || thermal == .critical)
	}

	private func startReachabilityMonitor() {
		#if canImport(Network)
			let monitor = NWPathMonitor()
			pathMonitor = monitor
			monitor.pathUpdateHandler = { path in
				let online = path.status == .satisfied
				Task { @MainActor in Switchboard.instance.setState(.isOnline, active: online) }
			}
			monitor.start(queue: DispatchQueue(label: "com.switchboard.reachability"))
		#endif
	}
}
