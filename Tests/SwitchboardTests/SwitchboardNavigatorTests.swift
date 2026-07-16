//
//  SwitchboardNavigatorTests.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 7/16/26.
//

import Testing
@testable import Switchboard

private struct SampleRequest: Hashable, Identifiable, Sendable {
	var id: String { "sample" }
}

private struct OtherRequest: Hashable, Identifiable, Sendable {
	var id: String { "other" }
}

@MainActor struct SwitchboardNavigatorIsPresentedTests {
	@Test func reflectsPresentedSheetOfMatchingType() {
		let nav = SwitchboardNavigator()
		let binding = nav.isPresentedBinding(for: SampleRequest.self)

		#expect(!binding.wrappedValue)
		nav.present(sheet: SampleRequest())
		#expect(binding.wrappedValue)
		#expect(!nav.isPresentedBinding(for: OtherRequest.self).wrappedValue)
	}

	@Test func settingFalseDismissesMatchingSheet() {
		let nav = SwitchboardNavigator()
		nav.present(sheet: SampleRequest())

		nav.isPresentedBinding(for: SampleRequest.self).wrappedValue = false
		#expect(nav.sheet == nil)
	}

	@Test func settingFalseLeavesReplacementSheetAlone() {
		let nav = SwitchboardNavigator()
		nav.present(sheet: SampleRequest())
		nav.present(sheet: OtherRequest())

		nav.isPresentedBinding(for: SampleRequest.self).wrappedValue = false
		#expect(nav.sheet?.base is OtherRequest)
	}

	@Test func settingTrueIsANoOp() {
		let nav = SwitchboardNavigator()
		nav.isPresentedBinding(for: SampleRequest.self).wrappedValue = true
		#expect(nav.sheet == nil)
	}
}
