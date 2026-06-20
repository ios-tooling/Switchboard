//
//  SwitchboardState.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/19/26.
//

import Foundation


public struct SwitchboardState: RawRepresentable, Codable, Sendable, Hashable {
	let name: String
	
	public init(rawValue: String) {
		self.name = rawValue
	}
	
	public var rawValue: String { name }

	public static let isSignedIn = Self(rawValue: "isSignedIn")

	// Device conditions reflected by ``Switchboard/observeSystemStates()``.

	/// The device has network connectivity.
	public static let isOnline = Self(rawValue: "isOnline")
	/// Low Power Mode is enabled.
	public static let lowPowerMode = Self(rawValue: "lowPowerMode")
	/// The device is under thermal pressure (serious or critical).
	public static let thermalPressure = Self(rawValue: "thermalPressure")
	/// Protected (encrypted) data is available — i.e. the device has been unlocked.
	public static let protectedDataAvailable = Self(rawValue: "protectedDataAvailable")
}
