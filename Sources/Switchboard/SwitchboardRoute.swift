//
//  SwitchboardRoute.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/19/26.
//

import Foundation

/// An incoming, routable entry into the app — a notification, universal link, custom URL
/// scheme, Handoff/Spotlight activity, quick action, or widget tap. Handed to
/// ``SwitchboardClient/route(_:)`` and offered to clients until one claims it.
///
/// The payload is immutable once received, so this is `@unchecked Sendable`.
public struct SwitchboardRoute: @unchecked Sendable {
	/// How a notification surfaced.
	public enum NotificationSource: Sendable {
		case tapped, foreground, background
	}

	/// Where the route originated.
	public enum Origin: Sendable {
		case notification(NotificationSource)
		case universalLink
		case urlScheme
		case activity(String)   // NSUserActivity.activityType
		case shortcut(String)   // UIApplicationShortcutItem.type
		case widget
	}

	/// Whether this route expresses direct user intent — a tap, opened link, activity, or
	/// widget/shortcut — as opposed to a silent notification delivery. User-intent routes are
	/// buffered when they arrive before ``Switchboard/launched()``.
	public var isUserIntent: Bool {
		switch origin {
		case .notification(.background), .notification(.foreground): false
		default: true
		}
	}

	/// The deep-link URL this route carries, if any.
	public let url: URL?
	/// The raw payload (a notification's userInfo, an activity's userInfo, …).
	public let userInfo: [AnyHashable: Any]
	public let origin: Origin

	public init(url: URL?, userInfo: [AnyHashable: Any] = [:], origin: Origin) {
		self.url = url
		self.userInfo = userInfo
		self.origin = origin
	}

	/// A push/local notification. The deep link is read from `aps.data.url`.
	public static func notification(_ userInfo: [AnyHashable: Any], source: NotificationSource) -> SwitchboardRoute {
		SwitchboardRoute(url: deepLink(in: userInfo), userInfo: userInfo, origin: .notification(source))
	}
	/// A universal (https) link the app was opened with.
	public static func universalLink(_ url: URL) -> SwitchboardRoute { SwitchboardRoute(url: url, origin: .universalLink) }
	/// A custom URL-scheme open.
	public static func urlScheme(_ url: URL) -> SwitchboardRoute { SwitchboardRoute(url: url, origin: .urlScheme) }
	/// A widget / Live Activity deep link.
	public static func widget(_ url: URL) -> SwitchboardRoute { SwitchboardRoute(url: url, origin: .widget) }
	/// A Home Screen quick action.
	public static func shortcut(type: String, url: URL? = nil) -> SwitchboardRoute { SwitchboardRoute(url: url, origin: .shortcut(type)) }
	/// A Handoff / Spotlight / continued `NSUserActivity`.
	public static func activity(type: String, url: URL?) -> SwitchboardRoute { SwitchboardRoute(url: url, origin: .activity(type)) }

	private static func deepLink(in userInfo: [AnyHashable: Any]) -> URL? {
		guard let aps = userInfo["aps"] as? [String: Any],
				let data = aps["data"] as? [String: Any],
				let raw = data["url"] as? String else { return nil }
		return URL(string: raw)
	}
}
