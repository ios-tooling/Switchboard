//
//  SwitchboardNavigator.swift
//  Switchboard
//
//  Created by Ben Gottlieb on 6/21/26.
//

import SwiftUI

/// The app's central navigation state: the selected tab, a navigation stack per tab, and the
/// presented sheet/cover. It's `@Observable`, so SwiftUI views bind directly to it, and any
/// code (a route claimer, a button, a deep link) drives navigation through the same object.
///
/// Destinations stay app-defined and type-erased here — `NavigationPath` already holds any
/// `Hashable`, and the typed binding helpers bridge your tab/modal enums at the view layer.
///
/// ```swift
/// // tab bar
/// TabView(selection: nav.tabBinding(MainScreenTab.self, default: .home)) { … }
///
/// // a tab's stack
/// NavigationStack(path: nav.pathBinding(for: MainScreenTab.home)) { … }
///
/// // drive it from anywhere
/// nav.select(MainScreenTab.home)
/// nav.push(feedItem, tab: MainScreenTab.home)
/// nav.present(sheet: AppModal.mood(item))
/// ```
@MainActor @Observable public final class SwitchboardNavigator {
	public static let instance = SwitchboardNavigator()

	public init() { }

	// MARK: - Tabs

	/// The selected tab, type-erased. Set it with ``select(_:)`` / read it with ``tab(as:)``.
	public var selectedTab: AnyHashable?

	public func select(_ tab: some Hashable) { selectedTab = AnyHashable(tab) }

	public func tab<Tab: Hashable>(as type: Tab.Type) -> Tab? { selectedTab?.base as? Tab }

	/// A two-way binding for a tab picker / `TabView(selection:)`, falling back to `fallback`
	/// when nothing (or a different type) is selected.
	public func tabBinding<Tab: Hashable>(_ type: Tab.Type, default fallback: Tab) -> Binding<Tab> {
		Binding(get: { self.tab(as: Tab.self) ?? fallback }, set: { self.selectedTab = AnyHashable($0) })
	}

	// MARK: - Stacks (one per tab)

	private var paths: [AnyHashable: NavigationPath] = [:]

	/// A binding to a tab's navigation stack, for `NavigationStack(path:)`.
	public func pathBinding(for tab: some Hashable) -> Binding<NavigationPath> {
		let key = AnyHashable(tab)
		return Binding(get: { self.paths[key] ?? NavigationPath() }, set: { self.paths[key] = $0 })
	}

	/// Push a destination onto a tab's stack.
	public func push(_ value: some Hashable, tab: some Hashable) {
		paths[AnyHashable(tab), default: NavigationPath()].append(value)
	}

	/// Pop a tab's stack back to its root.
	public func popToRoot(tab: some Hashable) { paths[AnyHashable(tab)] = NavigationPath() }

	/// Pop the last destination off a tab's stack.
	public func pop(tab: some Hashable) {
		let key = AnyHashable(tab)
		guard let path = paths[key], !path.isEmpty else { return }
		paths[key]?.removeLast()
	}

	// MARK: - Modals

	/// The presented sheet, type-erased. Drive with ``present(sheet:)`` / bind with ``sheetBinding(_:)``.
	public var sheet: AnyHashable?
	/// The presented full-screen cover.
	public var cover: AnyHashable?

	public func present(sheet value: some Hashable) { sheet = AnyHashable(value) }
	public func present(cover value: some Hashable) { cover = AnyHashable(value) }
	public func dismiss() { sheet = nil; cover = nil }

	/// A binding for `.sheet(item:)` over your modal type.
	public func sheetBinding<Modal: Hashable & Identifiable & Sendable>(_ type: Modal.Type) -> Binding<Modal?> {
		Binding(get: { self.sheet?.base as? Modal }, set: { self.sheet = $0.map(AnyHashable.init) })
	}

	/// A binding for `.fullScreenCover(item:)` over your modal type.
	public func coverBinding<Modal: Hashable & Identifiable & Sendable>(_ type: Modal.Type) -> Binding<Modal?> {
		Binding(get: { self.cover?.base as? Modal }, set: { self.cover = $0.map(AnyHashable.init) })
	}

	/// A `Bool` binding reporting whether a modal of `type` is the presented sheet, for child
	/// APIs that take `isPresented: Binding<Bool>`. Setting it `false` dismisses the sheet only
	/// while that type is still up, so a sheet that replaced it isn't torn down. Setting it
	/// `true` is a no-op — present with ``present(sheet:)``, which supplies the actual value.
	public func isPresentedBinding<Modal>(for type: Modal.Type) -> Binding<Bool> {
		Binding(get: { self.sheet?.base is Modal }) { newValue in
			if !newValue, self.sheet?.base is Modal { self.sheet = nil }
		}
	}
}

public extension Switchboard {
	/// The shared navigation coordinator.
	static var navigator: SwitchboardNavigator { .instance }
}
