# Google Tasks for Mac

A native Mac app for Google Tasks with widgets. Built with SwiftUI + Mac Catalyst.

## Features

- Sign in with Google — no account setup needed
- View, add, complete, and delete tasks across all your task lists
- Drag to reorder tasks
- Due date support with overdue highlighting
- Mac widgets (small, medium, large, lock screen)
- Complete tasks directly from the widget

## Download

Download the latest release from [Releases](../../releases).

Open the DMG, drag **GoogleTask** to Applications, and launch.

> On first launch, macOS may show a security warning. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Requirements

- macOS 14 or later
- A Google account

## Build from Source

```bash
brew install xcodegen
xcodegen generate
open GoogleTask.xcodeproj
```

Set your own Team under **Signing & Capabilities**, then build with the **"My Mac"** destination.

You'll need a Google OAuth client ID from [Google Cloud Console](https://console.cloud.google.com) — add it to `Supporting/Info.plist` as `GIDClientID`.
