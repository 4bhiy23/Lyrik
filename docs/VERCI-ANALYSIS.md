# Verci 2.0.1: static analysis notes

Read-only inspection of `/Applications/Verci.app` (not modified, never launched past its license gate).
Tools: `plutil`, `codesign -d`, `otool -L`, `lipo`, `strings`, `assetutil`, `sips`, and the app's own log and
preferences. These notes are the evidence Lyrik was designed from. **Observed** means read directly from the
bundle. **Inferred** means a reasonable reading of those observations that could not be confirmed past the license screen.

## Bundle and metadata (observed)

| Item | Value |
|---|---|
| Bundle ID / version | `Playgroundbranch.Verci`, 2.0.1 (build 5) |
| Type | `LSUIElement` menu-bar agent, min macOS 15.0, built with the macOS 27 SDK / Xcode 27.1 |
| Binary | Universal (x86_64 + arm64) Swift, about 4 MB, hardened runtime, Developer ID signed |
| Entitlements | `automation.apple-events`, `files.user-selected.read-only`, `network.client` (not sandboxed) |
| Usage string | Apple Events "reads the current track and playback position from Spotify and Music… to show lyrics in time" |
| Frameworks | Sparkle 2.9 (updates via `verci.xyz/appcast.xml`), plus system SwiftUI, AppKit, Combine, QuartzCore, MapKit, NaturalLanguage, IOKit, Security, ImageIO, Symbols |
| Resources | `AppIcon.icns`, `Assets.car` (app icon only), `default.metallib`, MIT `LICENSE` (© Lakr Aream) |

## What the app does (observed from strings)

- **Purpose:** synced lyrics on the macOS **lock screen**, word by word. The tagline is "Lyrics on your lock screen, word by word".
- **Player integration:** polls with `NSAppleScript` (`app.lerics.applescript` queue). The script checks
  `if application id … is running`, then reads `player state`, `name`/`artist`/`duration of current track` and
  `player position`, and falls back to `current stream title`. It follows whichever player is playing, and Spotify if both are.
- **Artwork:** Spotify via `artwork url of current track`, Music via `raw data of artwork 1 of current track`.
  A palette is extracted for "Match the album cover" (`ArtworkColorSync`).
- **Lyrics:** LRCLIB (`/api/get`, `/api/search`) and NetEase Cloud Music (`/api/search/get`, `/api/song/lyric/v1`).
  Title clean-up regexes strip feat./remaster/version tails. Word-level vs line-level "tier", with interpolated word timing.
  Length matching ("from a version %+.1fs in length", "too far to time the words by"), an on-disk cache,
  and a per-song timing shift ("Lyrics 1 second earlier/later").
- **Lock screen:** `SkyLightOperator` resolves private SkyLight symbols (`SLSMainConnectionID`, `SLSSpaceCreate`,
  `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`) to place a window in a
  space above the lock screen. Lock state comes from `com.apple.screenIsLocked/Unlocked` and `CGSSessionScreenIsLocked`.
- **Other system integrations:** `IOPMAssertion PreventUserIdleDisplaySleep` ("Keep the screen awake" while playing),
  `tccutil reset AppleEvents` ("Ask for permission again"), deep link to Privacy › Automation, per-display enablement.
- **Styles (13):** Native Design (+ Notifications, Map, Money), Codestyle (+ Visual), Fisheye (+ Visual), Visual,
  Constellation, Branches, Web, Flashbang Visual, Ship. Fonts: SF Pro/Rounded, New York, Helvetica Neue, Avenir Next, Futura, Didot.
- **Shaders (`default.metallib`):** a `fisheye` distortion (position, size, strength, power) and a `motionBlur`
  layer effect (SwiftUI `Layer`, velocity).
- **Word icons:** maps lyric words to SF Symbols using the system's `CoreGlyphs.bundle/…/symbol_search.plist`
  plus a NaturalLanguage embedding.
- **Gallery window** (about 1180×740) with live style previews, pinning to the menu bar, onboarding
  (welcome → player → style → license), and a "What's new" sheet.
- **Licensing:** Polar license keys (2 device slots, 3-day offline grace). **Not touched and not reproduced.**

## Not determinable behind the license screen (inferred or replaced)

- Exact motion curves and timings. Lyrik uses its own springs and eases.
- How the Map and Money styles choose places and payees. Not reproduced; they rely on MapKit look-around tours and
  Apple-branded payment imagery.
- Exact unlocked-mode placement. Lyrik offers "On the desktop" (behind windows) or "Over windows" (click-through).

## Independence

Lyrik shares no code or assets with Verci. Every Swift file, the icon (drawn in code by
`scripts/make-icon.swift`), the demo verses and the styles are original. Shared ideas are limited to public
mechanisms: AppleScript dictionaries, the public LRCLIB/NetEase endpoints, and documented or widely known system APIs.
