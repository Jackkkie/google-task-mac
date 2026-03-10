# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
xcodegen generate   # Regenerate GoogleTask.xcodeproj from project.yml (required after any project.yml change)
bash make_dmg.sh    # Build DMG installer from latest maccatalyst DerivedData build
```

Build and run are done inside Xcode (⌘R). There is no CLI test runner.

## Architecture

**SwiftUI + WidgetKit** Mac Catalyst app for Google Tasks. The app uses iOS APIs and runs on Mac via Mac Catalyst.

### Targets

| Target | Type | Purpose |
| --- | --- | --- |
| `GoogleTask` | Application | Main app (iOS + Mac Catalyst) |
| `GoogleTaskWidget` | App Extension | WidgetKit extension |

### Key Data Flow

1. `AuthManager` — Google Sign-In, OAuth token refresh. After every token refresh, saves token to App Group UserDefaults (`accessToken` key) for widget access
2. `GoogleTasksService` — REST to `tasks.googleapis.com`
3. `WidgetDataService.update(tasks:isSignedIn:)` — serializes `[WidgetTask]` into App Group UserDefaults + calls `WidgetCenter.shared.reloadAllTimelines()`
4. `TaskWidgetProvider` — reads from App Group UserDefaults, no network calls
5. `CompleteTaskIntent` (AppIntent in `Shared/`) — reads token from App Group UserDefaults, calls PATCH API, updates cache, reloads widget

### Shared Code

`Shared/` is compiled into **both** targets:
- `WidgetTask.swift` — Codable bridge model between app and widget. Has `id`, `listId`, `title`, `dueDate`, `isOverdue`
- `CompleteTaskIntent.swift` — AppIntent for completing tasks from widget buttons

`WidgetTask.listId` is required so `CompleteTaskIntent` can call the correct API endpoint.

### App Group ID

`group.com.jk.googletaskonmac` — hardcoded in `WidgetDataService`, `TaskWidgetProvider`, `CompleteTaskIntent`, and both entitlements files.

### Google Sign-In

- `GIDClientID` in `Supporting/Info.plist` — OAuth client ID from Google Cloud Console
- Reversed client ID as URL scheme in same plist — required for OAuth redirect
- Token refreshed via `user.refreshTokensIfNeeded()` before every API call
- OAuth consent screen must be published to "Production" in Google Cloud Console (not Testing) for non-test users

### Project Generation

`.xcodeproj` is gitignored. `project.yml` (XcodeGen) defines everything. Run `xcodegen generate` after any change to `project.yml`.

---

## Lessons Learned

### Mac Catalyst Destination

**Always use "My Mac" destination in Xcode**, not "My Mac (Designed for iPad)".

- "Designed for iPad" = iOS app running on Mac via Rosetta/translation layer. App Groups, URL schemes, and AppIntents don't work correctly.
- "My Mac" = proper Mac Catalyst. Sign-in, URL schemes, and widgets all work.
- The DMG must be built from `Debug-maccatalyst/` in DerivedData, not `Debug-iphoneos/`.

### Widget Picker Registration

For the widget to appear in Mac's Edit Widgets screen, **two things are required**:

1. `TARGETED_DEVICE_FAMILY` must include `6` (Mac Catalyst) in `project.yml` — without it, `UIDeviceFamily` in the built Info.plist only has `[2]` (iPad) and macOS doesn't recognize the widget as Mac-compatible
2. The app must be **installed in `/Applications`** (not run from DerivedData) for the widget to appear in the Mac widget picker — install via DMG

### AppIntent / Interactive Widget (CompleteTaskIntent)

`cannot add handler to 3 from 1 - dropping` in logs = XPC process isolation issue on Mac Catalyst. `Button(intent:)` in widgets triggers this. The intent still executes correctly despite the error — it's cosmetic on macOS 26+.

### App Group UserDefaults

`UserDefaults(suiteName: "group.com.jk.googletaskonmac")` must be used for all data shared between app and widget. Regular `UserDefaults.standard` is not accessible across extension boundaries. The access token must be saved here so `CompleteTaskIntent` (which runs in the widget process) can authenticate API calls.

`Couldn't read values in CFPrefsPlistSource... Using kCFPreferencesAnyUser with a container is only allowed for System Containers` in logs is a known Mac Catalyst warning — App Group still works despite the log message.

### DMG Distribution

`make_dmg.sh` auto-finds the maccatalyst build in DerivedData. After building in Xcode with "My Mac" destination:

```bash
bash make_dmg.sh
```

The resulting `GoogleTasks.dmg` contains the app + Applications symlink. The app is already signed (from Xcode's automatic signing), so no additional codesign step is needed.

### Task Reordering

Google Tasks API `POST /tasks/v1/lists/{list}/tasks/{task}/move?previous={prevTaskId}` moves a task after `prevTaskId`. Omit `previous` to move to top. The local array is updated optimistically before the API call for instant UI feedback.

### App Icon

Generated as 1024×1024 PNG using a Swift CoreGraphics script. Blue background (`#4285F4` Google blue), white checklist icon via SF Symbol path. Stored in `Sources/Assets.xcassets/AppIcon.appiconset/` and `Widget/Assets.xcassets/AppIcon.appiconset/`.
