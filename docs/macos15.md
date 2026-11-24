# macOS 15 on Apple Silicon

This fork targets macOS 15.0 and later, **arm64 only**. It keeps the current upstream
features where the operating system provides the required capability.

## Compatibility

- macOS 26 and later keep native Liquid Glass. macOS 15 uses SwiftUI materials and
  AppKit `NSVisualEffectView`; controls and compact-bar actions remain functional.
- Window termination, number-format changes and Notes undo/redo use notifications
  available on macOS 15. Notes preserves synchronous undo/redo source updates.
- Programmatic textarea insertions start a separate undo group on macOS 15, so
  undo preserves the text typed immediately before the insertion.
- Custom commands retain their pseudo-terminal and working directory using the
  macOS 15-compatible spawn action.
- FoundationModels requires macOS 26. On macOS 15, the on-device Apple Intelligence
  provider reports unavailable; configured API and installed providers remain usable.
- Translation uses Apple's macOS 15 SwiftUI translation session. The existing checks
  for supported languages and installed language assets still apply.
- MCP OAuth callbacks and the OpenCode tool bridge use the macOS 15 Network
  framework APIs. Loopback binding, authentication, request limits and cancellation
  are preserved.
- The fork's bundle identifiers are `com.tifasky.tinycast` and, for Debug,
  `com.tifasky.tinycast.dev`. Data and privacy grants are separate from upstream.
  These identifiers do not join upstream's automatic update channels, so an upstream
  macOS 26-only package cannot replace this build. Deep links use `tinycast-sequoia://`
  (Debug: `tinycast-sequoia-dev://`), keeping upstream's URL handlers separate.
- iCloud sync still requires the signer's own provisioning profile and entitlements.
  The default contributor build does not include iCloud capabilities.

## Build

Use Xcode 26.2 or later with a macOS 26 SDK, XcodeGen, and an Apple Silicon Mac.
The SDK version and the minimum runtime version are independent; do not switch to
Xcode 16 just because the deployment target is 15.0.

Generate the committed project after changing `project.yml`:

```bash
xcodegen generate
```

Build without requiring an Apple developer signing identity:

```bash
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Ad-hoc sign the local test app and its embedded code:

```bash
codesign --force --deep --sign - "build/DerivedData/Build/Products/Debug/Tinycast Dev.app"
```

Launch the actual app:

```bash
open "build/DerivedData/Build/Products/Debug/Tinycast Dev.app"
```

For stable Accessibility grants across rebuilds, use the existing self-signed
identity setup in [signing.md](signing.md). Ad-hoc signatures can require granting
Accessibility again after a rebuild. Distribution signing and notarization are
separate from this contributor build.

## Verify

Run the standalone harnesses and repository checks:

```bash
./Scripts/run-tests.sh
```

```bash
./Scripts/lint.sh
```

Check the main executable and every bundled helper with `lipo -archs` and
`xcrun vtool -show-build-version`: each must contain arm64 and declare a 15.0 floor.
New-system glass and FoundationModels imports must be weak. A successful compile
alone does not establish that an app launches on macOS 15.

On macOS 15, check launcher search and calculator results, expanded and compact
surfaces over a light desktop, settings, Notes editing/undo/redo, and translation
with installed assets. Accessibility, microphone, calendar and camera grants remain
user decisions; do not grant them automatically during verification.

## Verification record

Verified on macOS 15.8.1 (Apple Silicon) with Xcode 26.2 / Swift 6.2.3:

- All 117 standalone harnesses passed: 116 in the full run, with MCPStdioTests
  rerun successfully after a formatting edit interrupted its initial compilation.
- Debug app and embedded helpers build successfully. The App Intents metadata tool
  emits its existing no-AppIntents-dependency warning; Swift compilation has no warnings.
- Every bundled Mach-O file is arm64 with `minos 15.0`. Both app Info.plists declare
  `LSMinimumSystemVersion = 15.0`, and glass/FoundationModels symbols are weak imports.
- Ad-hoc signature passes `codesign --verify --deep --strict`.
- The app launches on macOS 15 and stays in the AppKit event loop.
- Repository lint, localization, settings search and migration checks pass.

The native UI automation tool could not discover the newly built app by bundle ID
or display name, despite the process running and LaunchServices registration.
Consequently screenshot/click verification is incomplete. Real translation with
installed language assets, microphone/camera/Accessibility interactions, and the
macOS 26 appearance branch have not been manually verified.

Intel is outside this fork's support scope. The upstream release workflow and
Homebrew instructions are retained as upstream references; they do not package or
publish this fork.
