# SlopShot

> A screenshotting app for yappers.

## Status

This document is the initial source of truth for SlopShot. It records the product intent, settled v1 behavior, recommended architecture, distribution model, acceptance criteria, and explicitly deferred work. It is not an implementation specification for features outside this scope.

## Product intent

SlopShot is a local-first macOS menu-bar screenshot utility for yappers: capture a bug or other visual context, then put the explanation directly into the screenshot and its metadata. It should feel like the native macOS screenshot tool: the user captures a screen, area, or window, briefly describes the issue, and receives one PNG that carries the description both visibly and as machine-readable metadata.

The problem it solves is the friction of taking a screenshot, finding the file, remembering the relevant context, and separately explaining that context to an agent. SlopShot keeps capture and explanation in one short interaction.

The product should remain a focused utility. It has no Dock icon, main window, account, cloud service, telemetry, or network activity other than an explicit update check.

Every SlopShot surface follows a strict minimal-design rule: use native macOS typography and behavior, generous negative space, and as few visible controls as possible. Avoid dashboards, nested cards, decorative pills, heavy borders, and unnecessary explanatory copy. The result should feel calm and obvious rather than styled for its own sake.

## Version 1 experience

### Capture

- `Command-Option-3` captures all displays.
- `Command-Option-4` starts the native macOS area-selection interaction. Pressing Space switches to window selection, matching the native behavior.
- `Command-Option-5` starts the same area/window capture, focuses the prompt composer when capture finishes, and fires an optional user-configured chained shortcut.
- All three capture shortcuts can be changed in Settings.
- SlopShot delegates capture to `/usr/sbin/screencapture` so that area and window selection use the familiar macOS interaction.
- SlopShot provides its own post-capture thumbnail because the system thumbnail cannot return a pending capture to the app for prompt processing.
- Captures are PNG files saved to Location 1, which defaults to Desktop, using the Mac's current screenshot prefix and exact `Screenshot <date> at <time>.png` convention. Name collisions use the native ` (2)`, ` (3)`, and subsequent suffixes and never overwrite an existing file.
- Settings exposes two independent save locations. Return saves to Location 1; Command-Return saves to Location 2. Both default to Desktop, and auto-save uses Location 1.
- Every completed capture is also copied to the clipboard. Annotated captures copy the final annotated PNG; multi-display captures expose all saved files and PNG data.

### Prompt thumbnail

After a successful capture, SlopShot displays a borderless thumbnail in the bottom-right corner of the relevant screen with a text field beneath the image.

- The idle window defaults to five seconds.
- The empty, unfocused composer shows a live `Auto-saves in <seconds>s` countdown.
- Settings can change the idle delay to 3, 5, 7, or 10 seconds.
- If the user does nothing, SlopShot saves the original PNG unchanged.
- Placing the cursor in the field or otherwise interacting with it permanently disables idle dismissal for that prompt.
- Return commits the prompt.
- Command-Return commits the prompt to Location 2.
- The prompt stays visible until the final PNG is saved and accepted by the clipboard; dismissal means the file is ready to paste.
- Shift-Return inserts a newline.
- Escape discards the prompt and saves the original screenshot.
- The field is a standard native macOS text control, so macOS Dictation and third-party transcription utilities can type into it. SlopShot does not record audio, request microphone access, or perform transcription.
- Chained capture can synthesize one configured shortcut after focusing the prompt, enabling third-party dictation workflows. This optional feature requires macOS Accessibility permission; ordinary capture does not.
- The thumbnail is for prompt entry only. It does not provide markup, cropping, drag-out, or sharing controls.

Multiple captures may remain pending independently. A full-screen capture on a multi-display system creates one PNG per display but presents one grouped prompt interaction. Every image in the group receives the same prompt and a shared capture ID.

### Prompt embedding

When a nonblank prompt is committed, its raw text is always written into image metadata.

Visual prompt text is enabled by default. In that mode, SlopShot expands the canvas downward and appends a dark, high-contrast footer separated from the captured pixels by a clear neutral divider:

```text
Prompt
<the complete prompt>
```

The footer wraps multiline text without cropping it. It never overlays, scales, or removes pixels from the original capture. Its text size defaults to Small and can be set to Small, Medium, or Large in Settings.

If visual prompt text is disabled, SlopShot still appends a small footer, but it contains only:

```text
Agent: Read the SlopShot prompt embedded in this image's metadata.
```

The complete prompt remains in metadata in this mode. If no prompt is entered, SlopShot adds neither a footer nor SlopShot metadata and moves the original screenshot without decoding or rewriting it.

### Menu-bar interface

SlopShot runs as a menu-bar-only application. Its menu contains:

- Settings
- Check for Updates...
- Quit SlopShot

Settings contains:

- A shortcut recorder for full-screen capture
- A shortcut recorder for area/window capture
- A `Command-Option-5` chained-capture recorder and an optional clearable target-shortcut recorder
- A configurable 3, 5, 7, or 10-second auto-save delay
- Two independently selectable save locations, both defaulting to Desktop
- A toggle for embedding the complete prompt visibly, enabled by default
- A Small, Medium, or Large saved-image prompt-size selector
- A launch-at-login toggle, disabled by default

Preferences persist locally. PNG is the only image format in v1.

## Technical direction

### Platform and project structure

- Native Swift 6 application for Apple silicon and macOS 14 Sonoma or newer.
- Swift Package Manager for source organization, dependencies, and tests.
- AppKit for the application lifecycle, `NSStatusItem`, global hotkeys, borderless prompt panels, text focus, and display positioning.
- SwiftUI for the small Settings panel.
- The `KeyboardShortcuts` Swift package wraps Carbon global-hotkey registration so capture shortcuts work while other applications are focused without Accessibility or Input Monitoring access. Only optional chained-shortcut emission requests Accessibility.
- The chained target is stored as a physical key chord. Left and right Command, Option, Control, and Shift are recorded and replayed independently, along with Fn, so dictation shortcuts such as Right Option + `/` retain their exact meaning.
- While the chained-target recorder is armed, a temporary event tap consumes the recorded chord so the dictation app does not execute it. Escape cancels recording. The tap exists only for the recording interaction and requires Accessibility.
- Core Graphics and Core Text for lossless canvas expansion and footer rendering.
- Image I/O for PNG encoding and metadata writing and verification. See [Apple's Image I/O documentation](https://developer.apple.com/documentation/imageio).
- `SMAppService` for optional launch at login.
- `UserDefaults` for local preferences.
- Third-party Swift code is statically linked into the app; SlopShot has no separately installed runtime dependencies.

Repository scripts will build the arm64 release executable, assemble the `.app` bundle and `Info.plist`, ad-hoc sign the bundle, run tests, and package the release archive. The bundle identifier is `com.prashantbhudwal.slopshot`.

Prototype builds use an explicit stable designated requirement for that bundle identifier so rebuilding does not invalidate the existing Screen Recording grant. This deliberately weak local-development identity must be replaced by a Developer ID signature before public production distribution.

### Capture and file lifecycle

Each invocation creates a capture session with a UUID and unique temporary paths. SlopShot runs `screencapture` as a child process and waits for it to finish. Cancellation produces no output file or error notification.

Unannotated screenshots are moved from the temporary location to the selected save path without image re-encoding. Annotated screenshots are written to a second temporary file, read back to verify their pixels and metadata, and then atomically moved to the final path. The original temporary capture remains available until all transformed outputs have been committed successfully.

If annotation fails, SlopShot must preserve and save the original capture rather than lose it. It should report that the prompt could not be attached. For grouped multi-display captures, successfully produced originals must not be discarded because another display failed.

The application must account for the macOS Screen Recording permission lifecycle and clearly report when capture permission is missing. Delegating to `/usr/sbin/screencapture` is a deliberate prototype tradeoff: it maximizes native interaction fidelity for direct distribution but must be reconsidered before Mac App Store distribution. ScreenCaptureKit is the public-framework fallback. See [Apple's ScreenCaptureKit documentation](https://developer.apple.com/documentation/ScreenCaptureKit).

### Metadata contract

The raw prompt is stored in both the standard PNG Description field and a versioned SlopShot XMP namespace. The initial schema contains:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Metadata schema version, initially `1` |
| `captureId` | UUID shared by all images from the same capture action |
| `prompt` | Exact committed prompt text |
| `capturedAt` | Capture timestamp in ISO 8601 UTC form |
| `displayIndex` | One-based index of this image in a grouped capture |
| `displayCount` | Total number of images in the grouped capture |
| `visualPromptEmbedded` | Whether the complete prompt, rather than only the metadata pointer, appears in the footer |

Metadata round-tripping must preserve the prompt exactly, including Unicode and line breaks. Existing safe screenshot metadata should be retained when the annotated PNG is encoded.

## Prototype distribution and updates

The source and releases live in the public GitHub repository `prashantbhudwal/slopshot`.

- The app installs to `~/Applications/SlopShot.app`, avoiding administrator privileges.
- Version tags trigger a GitHub Actions workflow that runs the verification suite, builds the arm64 app, validates the packaged bundle, and publishes the release assets.
- Each release publishes `SlopShot-arm64.zip` and a corresponding SHA-256 checksum.
- A shell installer downloads the release, verifies its checksum, validates the expected bundle identifier and arm64 architecture, installs it, applies ad-hoc signing if required, and explicitly removes the Gatekeeper quarantine attribute with `xattr`.
- The app performs no automatic or background update checks.
- The user can choose **Check for Updates...**, which queries the public latest GitHub Release, compares versions, and offers an available update.
- An accepted update is downloaded and checksum-verified, then staged outside the running bundle. A helper replaces the complete app bundle after SlopShot quits, preserves the previous bundle for rollback, and relaunches the app.
- Update failure must leave the currently installed version launchable.

This ad-hoc signed, unnotarized flow is for prototype testing only. Production distribution will require a reassessment of signing, notarization, and update authenticity.

## Privacy and security principles

- Screenshots and prompts remain entirely on the Mac unless the user manually sends the resulting file elsewhere.
- SlopShot has no account system, analytics, telemetry, advertising, or crash-upload service.
- The only network operation is a user-initiated request to the public GitHub Releases API and the corresponding asset download.
- Screen Recording is the only capture-related system permission expected in v1.
- Update replacement is accepted only after validating the checksum, bundle identifier, architecture, and version.

## Validation and acceptance criteria

### Automated tests

Unit tests must cover:

- Native-style filename generation and collision handling
- Shortcut encoding, validation, conflicts, and persistence
- Footer sizing, wrapping, Unicode, and multiline prompts
- Pixel preservation above the appended footer
- PNG Description and XMP metadata round-tripping
- Shared capture IDs and display indices for grouped captures
- Semantic version comparison and release parsing
- Archive checksum, bundle identifier, and architecture validation
- Atomic save and update rollback behavior

Integration and manual tests must cover:

- Full-screen, area, and window captures
- Capture cancellation
- Multiple displays and partially failed grouped captures
- Concurrent pending prompt thumbnails
- Five-second dismissal and all keyboard behaviors
- First-run Screen Recording permission and recovery after denial
- Operation while another application is focused
- Settings persistence and launch at login
- Original-file preservation after annotation failure
- Successful update, failed update, rollback, and relaunch
- macOS 14 compatibility before claiming it as supported

### Release acceptance

Version 1 is acceptable when:

- All three background capture shortcuts reliably begin the intended capture.
- An untouched capture reaches the selected save location without pixel or metadata rewriting.
- An annotated PNG visibly contains the selected footer behavior.
- Metadata inspection returns the exact prompt entered by the user.
- All images in a multi-display capture share one capture ID and prompt.
- A failed annotation or update never loses the original screenshot or working installed app.
- No screenshot or prompt leaves the Mac through SlopShot.

## Explicitly deferred

- Screen and audio recording
- Native-style markup or cropping
- Share sheet integration
- Direct integrations with agents or agent APIs
- Built-in speech transcription
- Intel Mac support
- Mac App Store packaging
- Developer ID signing and notarization
- Background or automatic update checks
- GitHub Actions and release automation
- Alternate image formats
