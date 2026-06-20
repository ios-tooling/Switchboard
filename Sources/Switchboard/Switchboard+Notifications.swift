//
//  Switchboard+Notifications.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/19/26.
//

#if canImport(UserNotifications)
import UserNotifications

public extension Switchboard {
	/// Opt Switchboard in as the `UNUserNotificationCenter` delegate. Tapped notifications are
	/// routed via ``route(_:)``; foregrounded ones are routed and then presented with
	/// `foregroundPresentation`.
	///
	/// This is an alternative to forwarding from your own delegate. It only covers the
	/// notification-center delegate (tap + foreground); silent/background remote notifications
	/// arrive through the app delegate and must still be forwarded to ``route(_:)`` there.
	func useAsNotificationDelegate(foregroundPresentation: UNNotificationPresentationOptions = [.banner, .sound]) {
		let delegate = SwitchboardNotificationDelegate(foregroundPresentation: foregroundPresentation)
		notificationDelegate = delegate   // the system holds the delegate weakly, so retain it
		UNUserNotificationCenter.current().delegate = delegate
	}
}

/// Bridges `UNUserNotificationCenterDelegate` (which requires an `NSObject`) into
/// ``Switchboard/route(_:)``, so ``Switchboard`` itself stays NSObject-free.
final class SwitchboardNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
	let foregroundPresentation: UNNotificationPresentationOptions

	init(foregroundPresentation: UNNotificationPresentationOptions) {
		self.foregroundPresentation = foregroundPresentation
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
		await Switchboard.instance.route(.notification(response.notification.request.content.userInfo, source: .tapped))
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
		await Switchboard.instance.route(.notification(notification.request.content.userInfo, source: .foreground))
		return foregroundPresentation
	}
}
#endif
