//
//  Switchboard+ResumeDaily.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/28/26.
//

import Foundation

extension Switchboard {
	static let lastResumeDailyKey = "com.switchboard.lastResumeDaily"

	/// Whether `.resumeDaily` should fire now, marking it if so. Fires at most once per local
	/// day. When ``resumeDailyAfterHour`` is set, it only fires once the local hour has reached
	/// it — before then it returns `false` *without* marking, so a later resume or foreground
	/// tick still delivers it that day (and a pre-hour open doesn't count as the day's resume).
	func shouldFireResumeDailyAndMark(now: Date = Date()) -> Bool {
		if let afterHour = resumeDailyAfterHour, Calendar.current.component(.hour, from: now) < afterHour { return false }
		if let last = resumeDailyDefaults.object(forKey: Self.lastResumeDailyKey) as? Date,
			Calendar.current.isDate(last, inSameDayAs: now) {
			return false
		}
		resumeDailyDefaults.set(now, forKey: Self.lastResumeDailyKey)
		return true
	}
}
