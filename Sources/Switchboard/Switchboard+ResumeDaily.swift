//
//  Switchboard+ResumeDaily.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/28/26.
//

import Foundation

extension Switchboard {
	private static let lastResumeDailyKey = "com.switchboard.lastResumeDaily"

	/// Returns `true` if no `.resumeDaily` has fired yet today (local calendar), marking now as
	/// the latest fire. Returns `false` — without updating — if one already fired today.
	func shouldFireResumeDailyAndMark() -> Bool {
		let defaults = UserDefaults.standard
		let now = Date()
		if let last = defaults.object(forKey: Self.lastResumeDailyKey) as? Date,
			Calendar.current.isDate(last, inSameDayAs: now) {
			return false
		}
		defaults.set(now, forKey: Self.lastResumeDailyKey)
		return true
	}
}
