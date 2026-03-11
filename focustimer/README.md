# FocusTimer (macOS)

FocusTimer is a SwiftUI macOS app with focus/break cycles and smart session setup.

## Architecture Goals

1. Keep UI simple and thin.
2. Keep business logic testable and isolated.
3. Keep integrations (notifications, cloud sync) behind service interfaces.
4. Make it safe to add features without creating one large file again.

## Project Structure

- `Sources/FocusTimer/App`
- `Sources/FocusTimer/Features`
- `Sources/FocusTimer/Domain`
- `Sources/FocusTimer/Services`
- `Sources/FocusTimer/Storage`

## Status Bar Timer Structure

- `Sources/FocusTimer/Features/Timer/StatusBarTimerView.swift`: primary status bar UI and interaction flow.
- `Sources/FocusTimer/Features/Timer/StatusBarTimerFrontCard.swift`: front/focus card presentation and focus task row rendering.
- `Sources/FocusTimer/Features/Timer/StatusBarTimerTheme.swift`: centralized design tokens and color/material theme values.
- `Sources/FocusTimer/Features/Timer/StatusBarTimerDraftHelpers.swift`: duration formatting and draft normalization helpers.
- `Sources/FocusTimer/Features/Timer/StatusBarTimerUIComponents.swift`: shared UI building blocks (toolbar buttons, rows, pills, divider).
- `Sources/FocusTimer/Features/Timer/StatusBarTimerSettingsComponents.swift`: settings-specific reusable components (header, setup cards, AI status footer).
- `Sources/FocusTimer/Features/Timer/StatusBarEditableSubtaskRow.swift`: editable sub-task row component with hover/focus/reorder-safe behavior.
- `Sources/FocusTimer/Features/Timer/StatusBarEmojiColorPickerPopover.swift`: shared emoji+color picker UI used by both main task and sub-task editing.
- `Sources/FocusTimer/Features/Timer/SuggestionTaskBag.swift`: central cancellation bag for in-flight AI suggestion tasks.
- `Sources/FocusTimer/Features/Timer/SuggestionRequestGate.swift`: stale-request guard so older AI responses cannot overwrite newer input.
- `Sources/FocusTimer/Features/Timer/SubtaskDropDelegate.swift`: drag/drop reordering behavior for sub-tasks.
- `Sources/FocusTimer/Features/Timer/StatusBarTimerSupport.swift`: window/material behavior and size measurement helpers.
- `Sources/FocusTimer/Features/Timer/Color+Hex.swift`: UI color conversion helpers.

## Shared Domain Rules

- `Sources/FocusTimer/Domain/SessionCategory.swift`: single source of truth for category name, emoji, color, and matching keywords.
- `Sources/FocusTimer/Domain/HexColor.swift`: shared hex normalization used by both UI and services.
- `Sources/FocusTimer/Domain/Character+Emoji.swift`: shared emoji detection helpers.

These shared types intentionally remove duplicated parsing and palette logic from views/view models/services.

## Layer Responsibilities

- `App`: app entrypoint and dependency wiring only.
- `Features`: SwiftUI views and feature-specific view models.
- `Domain`: pure models and core domain types.
- `Services`: side effects and OS/system integrations.
- `Storage`: persistence and sync logic.

## Dependency Rules

1. `View` can depend on `ViewModel`, `Domain`, and shared UI components.
2. `ViewModel` can depend on `Domain`, `Services`, and `Storage`.
3. `Services` can depend on OS frameworks and Foundation.
4. `Domain` must not depend on `View`, `Services`, or `Storage`.
5. `Storage` must not depend on `View` types.
6. No cross-feature imports unless extracted into `Domain` or shared components.

## State and Data Flow

1. User input updates `ViewModel`.
2. `ViewModel` mutates published state.
3. `View` renders from published state only.
4. Side effects are triggered by `ViewModel` through protocols.
5. Persisted settings are loaded on startup and saved through `SettingsStore`.

## Persistence and Sync

- `SettingsStore` is the single place for settings read/write.
- Local storage uses `UserDefaults`.
- Shared JSON serialization in storage flows through `Sources/FocusTimer/Storage/StorageJSONCodec.swift`.
- Settings cloud sync uses CloudKit (private database, last-write-wins via `updatedAt`).
- Task library cloud sync uses CloudKit (private database, last-write-wins via `updatedAt`).
- Cloud pushes are debounced/coalesced to reduce write bursts and race pressure.
- External cloud updates flow back into `TimerViewModel`.

## Concurrency Rules

1. `TimerViewModel` is `@MainActor`.
2. UI state updates happen on main actor.
3. Potentially blocking tasks run off main thread.
4. Return to main actor before mutating `@Published` state.

## Coding Standards

1. One primary type per file.
2. Keep files focused; split when a file becomes multi-responsibility.
3. Prefer protocol-driven services for anything with side effects.
4. Avoid global mutable state.
5. Keep strings and constants close to the feature they belong to.

## Category/AI Suggestion Notes

1. If category colors/emojis/keywords change, update `Sources/FocusTimer/Domain/SessionCategory.swift`.
2. `SessionSetupSuggester` consumes that file directly; avoid redefining palette data in UI/services.
3. Keep free-text color aliases in `SessionSetupSuggester` only for non-category names (e.g. "purple", "blue").

## Build

```bash
swift build
```

## Next Engineering Steps

1. Expand coverage around AI suggestion parsing and normalization edge-cases.
2. Add UI refinement without changing architecture boundaries.
