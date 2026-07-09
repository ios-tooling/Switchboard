//
//  Switchboard+LaunchVersion.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 7/9/26.
//

import Foundation

extension Switchboard {
	static let lastLaunchedVersionKey = "com.switchboard.lastLaunchedVersion"

	/// Whether this launch warrants `.firstLaunch` (no version recorded yet) or `.launchNewVersion`
	/// (a recorded version that differs from `currentVersion`), recording `currentVersion` either
	/// way so the next launch compares against it. Returns `nil` when the version is unchanged, or
	/// when no version is available to compare. `currentVersion` defaults to the bundle's short
	/// version string (`CFBundleShortVersionString`, not the build number); overridable in tests.
	func launchVersionEventAndMark(currentVersion: String? = Switchboard.bundleShortVersion) -> SwitchboardEvent? {
		guard let currentVersion else { return nil }
		let stored = launchVersionDefaults.string(forKey: Self.lastLaunchedVersionKey)
		launchVersionDefaults.set(currentVersion, forKey: Self.lastLaunchedVersionKey)

		if stored == nil { return .firstLaunch }
		if stored != currentVersion { return .launchNewVersion }
		return nil
	}

	static var bundleShortVersion: String? {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
	}
}
