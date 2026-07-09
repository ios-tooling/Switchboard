# AGENTS.md — Switchboard

Single `@MainActor` lifecycle coordinator. Clients register once and receive **events**,
**state changes**, and **routes**. Dependency-free Swift package (Foundation + system frameworks
only). Platforms: iOS 17 / macOS 14 / tvOS 17 / visionOS 1 / watchOS 10. Swift 6.

## Build & test

```bash
swift build      # validates on the macOS host (zero external deps, macOS 14 declared)
swift test       # SwitchboardTests (Swift Testing)
```
No Xcode project needed. There are no external dependencies — **keep it that way** (the value of
this package is being a generic, dependency-free primitive). Use `os.Logger`, not a logging
package.

## Files (`Sources/Switchboard/`)

- `Switchboard.swift` — the `@MainActor` singleton: `register`, `launched`, `route`, `setState`,
  `has`, `cancel`, the system-notification observers, the foreground tick timer, `dispatch`, and
  the two `deliver` overloads — `deliver(_:to:)` (events) and `deliver(_:active:to:)` (state). Owns
  all stored state, including the two bookkeeping stores `resumeDailyDefaults` /
  `launchVersionDefaults` (both `UserDefaults`, overridable in tests) and `resumeDailyAfterHour`.
- `SwitchboardClient.swift` — the client protocol + **no-op default implementations**.
- `SwitchboardEvent.swift` — the `OptionSet` of events, `.all`, `notificationMappings`, and
  `CustomStringConvertible` (used by logging).
- `SwitchboardState.swift` — extensible string-backed state value + built-in constants
  (`.isSignedIn` + the device conditions).
- `SwitchboardRoute.swift` — the routable value + `Origin` + factory constructors.
- `Switchboard+ResumeDaily.swift` — `.resumeDaily` bookkeeping: `shouldFireResumeDailyAndMark(now:)`,
  fires once per local calendar day, held until `resumeDailyAfterHour`. Key
  `com.switchboard.lastResumeDaily`.
- `Switchboard+LaunchVersion.swift` — `.firstLaunch` / `.launchNewVersion` bookkeeping:
  `launchVersionEventAndMark(currentVersion:)` compares the bundle short version string
  (`CFBundleShortVersionString`) against the stored one. Key `com.switchboard.lastLaunchedVersion`.
- `SwitchboardNavigator.swift` — optional `@Observable @MainActor` navigation coordinator (selected
  tab, a `NavigationPath` per tab, sheet/cover), destinations type-erased via `AnyHashable`. The
  only file that `import SwiftUI`s. Independent of the client/event machinery; reached via
  `Switchboard.navigator`.
- `Switchboard+Notifications.swift` — opt-in `UNUserNotificationCenterDelegate` adapter
  (`useAsNotificationDelegate`). Guarded by `#if canImport(UserNotifications)`.
- `Switchboard+SystemStates.swift` — `observeSystemStates()`; reflects device conditions into
  state via `setState`. Uses `Network`/`ProcessInfo`/`UIApplication`.
- `Switchboard+Logging.swift` — `setLogging(events:states:)` + the hooks called from
  `dispatch`/`setState`.

## Invariants — do not break

- **`SwitchboardClient` is `AnyObject, Sendable` and NOT `@MainActor`.** This is deliberate: it
  lets both `@MainActor` classes and `actor`s conform (a `@MainActor` protocol cannot be
  satisfied by an actor). Async callbacks run in the client's own isolation. Do not add
  `@MainActor` to the protocol.
- **All client methods have no-op defaults.** A client implements only what it needs. Never
  reintroduce trapping (`fatalError`) defaults.
- Clients are stored **weakly** and dispatched **sequentially in registration order** (the
  responder chain for `route`, and the loops in both `deliver` overloads).
- `.launch` is never auto-fired on register — the app calls `launched()` after all clients are
  registered (preserves order). System events are observed lazily on first `register`.
- `setState` notifies only on an actual change (`Set.insert(_:).inserted` / `remove(_:) != nil`).
- `has(state:)` / `setState(_:active:)` are `@MainActor`. Actor clients read them with `await`.

## The three primitives

- **Events** — `SwitchboardEvent` OptionSet → `dispatch(_:)` → `deliver(_:to:)` calls the
  matching `onX()`. System events come from `notificationMappings`; `.timeChange` from
  `significantTimeChange`; `.tick` from a 15-min foreground-only `Task` timer (started on
  launch/resume, stopped on background). **Derived events** are computed inside `dispatch` from the
  UserDefaults bookkeeping helpers, *not* from notifications: `.firstLaunch` / `.launchNewVersion`
  ride just ahead of `.launch`; `.resumeDaily` rides just after `.resume`/`.tick`. Delivery order
  in `deliver(_:to:)` places each derived event on the intended side of its base event.
- **State** — `Set<SwitchboardState>`; `setState` → `deliver(_:active:to:)` →
  `onStateChange(_:isActive:)`. Per-state, precise (one state + bool), not a whole-set dump.
  `.isSignedIn` additionally fans out to the `onSignIn()` / `onSignOut()` convenience callbacks,
  delivered just after `onStateChange` for that state.
- **Routing** — `route(_ route:) async -> Bool` offers a `SwitchboardRoute` to each client until
  one returns `true`.

## Navigation (optional, separate from clients)

`SwitchboardNavigator` (`Switchboard.navigator`) is a standalone `@Observable` coordinator for
tab + per-tab stack + sheet/cover. It is **not** part of the client/event system: SwiftUI views
bind to it directly and route claimers drive it. Destinations are app-defined and type-erased
(`AnyHashable`). It's the only file that imports SwiftUI.

## How to extend

- **Add an event:** add the case in `SwitchboardEvent` (next free bit) + include it in `.all` +
  add to `notificationMappings`/`CustomStringConvertible` if applicable; add `onX()` to
  `SwitchboardClient` **with a no-op default**; add the `if events.contains(.x)` line in
  `Switchboard.deliver(_:to:)`. For a **derived** event (computed, not notification-driven), add a
  `Switchboard+X.swift` helper with a `…AndMark`-style method backed by its own overridable
  `UserDefaults`, insert it in `dispatch`, and order its `deliver` line relative to the base event
  (see ResumeDaily / LaunchVersion).
- **Add a built-in state:** add a `static let` to `SwitchboardState`; if it's a device condition,
  observe it in `Switchboard+SystemStates` and drive it with `setState`. To give a state a
  dedicated convenience callback (like `.isSignedIn` → `onSignIn`/`onSignOut`), add the `onX()`
  methods to `SwitchboardClient` with no-op defaults and fan out from `deliver(_:active:to:)`.
- **Add a route origin:** add an `Origin` case + a factory to `SwitchboardRoute`. Clients claim
  it in `route(_:)` (usually by `route.url`).

## Gotchas

- APNS `userInfo` is `[AnyHashable: Any]` (not `Sendable`); `SwitchboardRoute` is therefore
  `@unchecked Sendable` (immutable after receipt). When forwarding from a non-isolated delegate,
  build the `SwitchboardRoute` **before** the `Task` (don't capture the non-Sendable
  `UNNotification` inside it).
- `useAsNotificationDelegate` installs an `NSObject` adapter (`SwitchboardNotificationDelegate`)
  because `UNUserNotificationCenterDelegate` requires `NSObject` — `Switchboard` itself stays
  NSObject-free. The system holds the delegate weakly, so it's retained in
  `notificationDelegate`.
- `.isOnline` is seeded asynchronously (the `NWPathMonitor` first callback). `.thermalPressure`
  is a boolean distillation (serious|critical) — the state set holds flags, not levels.
- `observeSystemStates()` and `useAsNotificationDelegate()` are opt-in and idempotent.