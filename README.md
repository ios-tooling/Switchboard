# Switchboard

A single, lightweight coordinator for an iOS/macOS app's lifecycle. Instead of scattering
`NotificationCenter` observers, app-delegate hooks, and deep-link parsing across your codebase,
your stores and managers register once with **Switchboard** and receive exactly the callbacks
they implement.

Switchboard has three jobs:

- **Events** — launch, foreground/background, terminate, low-memory, a periodic tick, time changes.
- **State** — an extensible set of sticky conditions (signed-in, online, low-power, …) that clients react to and can query.
- **Routing** — one responder chain for everything that can *open* your app: notifications, universal links, URL schemes, Handoff/Spotlight activities, quick actions, widgets.

It's a small, dependency-free Swift package (Foundation + the system frameworks only).

## Requirements

iOS 17 · macOS 14 · tvOS 17 · visionOS 1 · watchOS 10 · Swift 6.

## Installation

```swift
.package(url: "https://github.com/ios-tooling/Switchboard", from: "1.0.0")
```

## Quick start

Conform a store or manager to `SwitchboardClient` and implement only the callbacks you care
about — everything else defaults to a no-op:

```swift
import Switchboard

@MainActor final class FeedStore: SwitchboardClient {
    static let instance = FeedStore()

    func onLaunch() async { await refresh() }
    func onResume() async { await refresh() }

    func onStateChange(_ state: SwitchboardState, isActive: Bool) async {
        if state == .isOnline, isActive { await refresh() }   // refresh when we reconnect
    }
}
```

Register your clients at startup (in dependency order), then signal launch:

```swift
let board = Switchboard.instance
board.observeSystemStates()                 // optional: reflect device conditions into state
board.register(ProfileManager.instance)     // earlier clients are notified first
board.register(FeedStore.instance)
board.launched()                            // fire .launch to everyone, in order
```

Clients are held **weakly** and notified **sequentially in registration order**. Each callback
runs in the client's own isolation — a `@MainActor` class on the main actor, an `actor` on its
own executor — so both conform without ceremony.

## Events

| Event | Fires when |
|---|---|
| `.launch` | you call `board.launched()` |
| `.firstLaunch` | the app launches for the first time on this device (just before `.launch`) |
| `.launchNewVersion` | the first launch after the app's version string changes (just before `.launch`) |
| `.resume` | the app becomes active |
| `.willEnterForeground` | the app is about to enter the foreground |
| `.background` | the app enters the background |
| `.terminate` | the app is about to terminate |
| `.memoryWarning` | the system issues a low-memory warning |
| `.tick` | every 15 minutes while foregrounded |
| `.timeChange` | midnight/day rollover or timezone shift |

Each maps to a callback (`onResume()`, `onMemoryWarning()`, …). System events are observed for
you; `.launch` is the one you fire yourself, once clients are registered.

## State

`SwitchboardState` is an extensible, string-backed value — define your own alongside the
built-ins:

```swift
extension SwitchboardState {
    static let isPremium = SwitchboardState(rawValue: "isPremium")
}

board.setState(.isSignedIn, active: true)   // notifies clients via onStateChange(_:isActive:)
if board.has(state: .isOnline) { … }        // query at any time
```

`setState` only notifies when the value actually changes. Clients react in
`onStateChange(_ state:, isActive:)`.

The built-in `.isSignedIn` state also has convenience callbacks — implement `onSignIn()` /
`onSignOut()` instead of matching on `.isSignedIn` in `onStateChange`. They fire just after the
state change:

```swift
func onSignIn() async  { await loadAccount() }
func onSignOut() async { await clearAccount() }

board.setState(.isSignedIn, active: true)   // → onStateChange(.isSignedIn, true), then onSignIn()
```

### Device conditions

Call `observeSystemStates()` once and Switchboard keeps these in sync for you:

`.isOnline` (reachability) · `.lowPowerMode` · `.thermalPressure` (serious/critical) ·
`.protectedDataAvailable` (device unlocked). All are seeded synchronously except `.isOnline`,
whose first value arrives a moment after start.

## Routing

Anything that opens or deep-links your app becomes a `SwitchboardRoute`, offered to clients in
registration order until one **claims** it (returns `true`):

```swift
extension ActionController: SwitchboardClient {
    func route(_ route: SwitchboardRoute) async -> Bool {
        guard let url = route.url else { return false }
        return await handle(url)        // claim it
    }
}
```

Feed routes in from wherever they arrive:

```swift
await board.route(.universalLink(url))                       // onOpenURL
await board.route(.notification(userInfo, source: .tapped)) // a notification delegate
await board.route(.activity(type: activity.activityType, url: activity.webpageURL))
```

### Notifications

For push/local notifications you have two options:

- **Forward** from your existing `UNUserNotificationCenterDelegate` by calling
  `board.route(.notification(...))`.
- **Opt in** and let Switchboard be the delegate:

  ```swift
  board.useAsNotificationDelegate()   // routes taps + foreground presentations for you
  ```

  Silent/background pushes arrive through the app delegate, so forward those from
  `application(_:didReceiveRemoteNotification:)`.

## Debug logging

Turn on `os.Logger` output for any events (and a snapshot of states) while debugging:

```swift
board.setLogging()                                          // all events
board.setLogging(events: .resume, states: [.isSignedIn, .isOnline])
```

Logs each matching event with the listed states' values (`▸ resume · isSignedIn=true,
isOnline=false`) and each change to those states (`◆ isOnline → true`). Call `setLogging(events: [])`
to turn it back off.

## License

MIT.
