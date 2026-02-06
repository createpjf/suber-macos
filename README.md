# SubReminder for macOS

A native macOS menu bar app for tracking and managing your subscriptions. Built with Swift + SwiftUI.

This is the macOS native companion to the [SubReminder Chrome Extension](https://github.com/createpjf/subreminder).

## Features

- **Menu bar app** — lives in the macOS menu bar, always one click away
- **Calendar view** — visual monthly calendar showing upcoming billing dates
- **List view** — searchable, filterable, sortable subscription list
- **Light / Dark mode** — follows system appearance automatically
- **Chrome extension import** — import subscriptions exported from the Chrome extension
- **Multi-currency** — supports 20+ currencies (USD, EUR, CNY, JPY, etc.)
- **Notifications** — configurable reminders before billing dates
- **Data export / import** — JSON backup and restore

## Screenshots

| Calendar | List | Add Subscription |
|----------|------|-----------------|
| Calendar view with billing indicators | Filterable subscription list | Add/edit subscription form |

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Installation

### Download DMG

Download the latest `.dmg` from [Releases](../../releases), open it, and drag `SubReminder.app` to `Applications`.

> **Note:** The app is ad-hoc signed. On first launch, right-click the app → Open → Open to bypass Gatekeeper.

### Build from Source

```bash
# Clone
git clone https://github.com/createpjf/subreminder-macos.git
cd subreminder-macos

# Generate Xcode project (requires xcodegen)
xcodegen generate

# Build
xcodebuild build -project SubReminder.xcodeproj -scheme SubReminder -configuration Release

# Or build DMG
./scripts/build-dmg.sh
```

## Import from Chrome Extension

1. In the Chrome extension, go to Settings → Export JSON
2. In the macOS app, go to Settings → Import JSON
3. Select the exported file — subscriptions and settings will be imported

## Tech Stack

- Swift 5.9+, SwiftUI
- `MenuBarExtra` with `.window` style
- `UserDefaults` + `Codable` JSON persistence
- `xcodegen` for project generation
- 30 unit tests

## Project Structure

```
Sources/
├── SubReminderApp.swift          # App entry point (MenuBarExtra)
├── Models/
│   ├── Constants.swift           # Theme colors, currencies, categories
│   ├── Settings.swift            # AppSettings model
│   └── Subscription.swift        # Subscription model & form data
├── Services/
│   ├── BillingCalculator.swift   # Next billing date calculations
│   ├── NotificationService.swift # Local notification scheduling
│   └── StorageService.swift      # JSON persistence & import/export
├── Utilities/
│   ├── CurrencyFormatter.swift   # Currency display formatting
│   └── DateHelpers.swift         # Date formatting helpers
├── ViewModels/
│   ├── SettingsStore.swift       # Settings state management
│   └── SubscriptionStore.swift   # Subscription CRUD operations
└── Views/
    ├── MenuBarView.swift         # Root view with navigation
    ├── TopBarView.swift          # Navigation bar
    ├── CalendarView.swift        # Monthly calendar
    ├── CalendarDayCellView.swift # Calendar day cell
    ├── DayDetailView.swift       # Day detail popup
    ├── ListView.swift            # Subscription list
    ├── SubCardView.swift         # Subscription card
    ├── SubscriptionFormView.swift# Add/edit form
    ├── SettingsView.swift        # Settings page
    └── Components/               # Reusable UI components
Tests/
├── BillingCalculatorTests.swift
├── StorageServiceTests.swift
└── SubscriptionStoreTests.swift
```

## License

MIT
