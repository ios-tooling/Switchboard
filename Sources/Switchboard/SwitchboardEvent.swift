//
//  SwitchboardEvent.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/15/26.
//

import Foundation

#if os(iOS) || os(tvOS) || os(visionOS)
	import UIKit
#elseif os(macOS)
	import AppKit
#elseif os(watchOS)
	import WatchKit
#endif

/// One or more points in the app's lifecycle that a ``SwitchboardClient`` can be notified at.
public struct SwitchboardEvent: OptionSet, Sendable {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }

	/// The app has launched. Fired via ``Switchboard/launched()`` once clients are registered.
	public static let launch = SwitchboardEvent(rawValue: 1 << 0)
	/// The app became active (returned to the foreground).
	public static let resume = SwitchboardEvent(rawValue: 1 << 1)
	/// The app is about to enter the foreground (before it becomes active).
	public static let willEnterForeground = SwitchboardEvent(rawValue: 1 << 2)
	/// The app entered the background (resigned active on macOS).
	public static let background = SwitchboardEvent(rawValue: 1 << 3)
	/// The app is about to terminate.
	public static let terminate = SwitchboardEvent(rawValue: 1 << 4)
	/// The system issued a low-memory warning.
	public static let memoryWarning = SwitchboardEvent(rawValue: 1 << 5)
	/// A periodic tick while the app is foregrounded (every 15 minutes).
	public static let tick = SwitchboardEvent(rawValue: 1 << 6)
	/// A significant time change — midnight/day rollover or timezone shift.
	public static let timeChange = SwitchboardEvent(rawValue: 1 << 7)

	/// System events paired with the platform notification that drives them. `.launch`/`.tick`
	/// have no notification; `.timeChange` is observed separately by ``Switchboard``.
	static var notificationMappings: [(event: SwitchboardEvent, name: Notification.Name)] {
		var mappings: [(SwitchboardEvent, Notification.Name)] = []
		#if os(iOS) || os(tvOS) || os(visionOS)
			mappings.append((.resume, UIApplication.didBecomeActiveNotification))
			mappings.append((.willEnterForeground, UIApplication.willEnterForegroundNotification))
			mappings.append((.background, UIApplication.didEnterBackgroundNotification))
			mappings.append((.terminate, UIApplication.willTerminateNotification))
			mappings.append((.memoryWarning, UIApplication.didReceiveMemoryWarningNotification))
		#elseif os(macOS)
			mappings.append((.resume, NSApplication.didBecomeActiveNotification))
			mappings.append((.background, NSApplication.willResignActiveNotification))
			mappings.append((.terminate, NSApplication.willTerminateNotification))
		#elseif os(watchOS)
			if #available(watchOS 7.0, *) {
				mappings.append((.resume, WKApplication.didBecomeActiveNotification))
				mappings.append((.background, WKApplication.didEnterBackgroundNotification))
			}
		#endif
		return mappings
	}
}
