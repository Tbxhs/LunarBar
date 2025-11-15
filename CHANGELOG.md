# Changelog

## [2.2.3] - 2025-11-15
- Switched to create-dmg tool for professional DMG packaging.
- Completely eliminated .fseventsd and other system files from DMG.
- Improved icon positioning and window layout consistency.

## [2.2.2] - 2025-11-15
- Fixed DMG window layout to ensure all icons are visible on first open.
- Improved release script to automatically clean up mounted DMG volumes.

## [2.2.1] - 2025-11-15
- Fixed file permission request on first launch by moving user-defined holiday files from ~/Documents to ~/Library/Application Support.
- Improved user privacy and security by eliminating unnecessary Documents folder access.

## [2.2.0] - 2025-11-15
- Simplified menu structure by removing category headers and unused accessibility options.
- Enhanced "Pin on Top" feature with persistent state and visual checkbox indicator.
- Improved custom date format help with Chinese-friendly Wiki documentation and examples.
- Fixed window activation issues for About and Check for Updates dialogs to ensure they appear in front.
- Updated all localizations (English, Simplified Chinese, Traditional Chinese) for consistency.

## [2.1.1] - 2025-11-14
- Sparkle feed configuration rollout: publish appcast to gh-pages when signing tools and private key are available.
- Validation release for automatic in-app update (Install/Later/Skip) with Sparkle 2.

## [2.1.0] - 2025-11-14
- Integrate Sparkle 2 updater (code path). Uses Sparkle when available; falls back to GitHub page otherwise until appcast/signing are configured.
- Keep “Check for Updates…” menu; when Sparkle is present it shows an Install/Update flow.
- Prepare release tooling to also produce a ZIP for Sparkle distribution.

## [2.0.1] - 2025-11-14
- Menu: rename “System Symbol” to “Custom Symbol”.
- Alert: shorten title and help; show “More examples: Help” with hyperlink.
- Use a single Chinese wiki page for examples; remove in‑repo docs copy.
- Update localizations (en/zh‑Hans/zh‑Hant) for the new strings.

## [2.0.0] - 2025-11-05
- Refined date selection UI with perfectly circular indicators (40pt fixed size) to eliminate overlap.
- Unified the visual appearance of today's marker and selected date rings for consistency.
- Softened calendar event dot brightness for a more subtle visual presentation.
- Added 2026 public holiday data for Mainland China.
- Filtered expired events from the event list to show only current and upcoming items.
- Fixed update checker to handle empty release notes gracefully.

## [1.9.4] - 2025-11-05
- Simplified the right-click menu layout to surface the most common actions with fewer taps.
- Resolved menu bar icon rendering bugs so custom icon styles now display consistently.
- Tuned calendar spacing to keep the popover content aligned at every scale.
- Updated the DMG packaging to restore the classic “drag to Applications” layout with centered icons.

## [1.9.3] - 2025-11-04
- Added a right-click context menu to the calendar for faster access to navigation and settings.
- Replaced the legacy Actions button with the new menu, reducing visual clutter.
- Refined various UX details and polished wording across localized menu items.

## [1.9.2] - 2025-11-03
- Improved event list display by removing strikethrough styling for completed tasks.
- Added visual distinction for past events with reduced opacity (gray appearance).
- Fixed version comparison logic to properly detect updates (only notify when remote version is newer).
- Enhanced DMG packaging with drag-to-install interface.

## [1.9.1] - 2025-06-13
- Added configurable spacing between calendar cells to prevent today's highlight from overlapping adjacent selections.
- Updated calendar popover sizing to account for the new inter-cell spacing.
- Implemented event list view that displays events for selected dates.
- Added date selection functionality with automatic today selection on popover open.
- Integrated event clicking to open system Calendar app at the event's date.

## [1.9.0] - 2025-06-12
- Switched the menu bar status item to a fixed `M月d日 EEE` format with Chinese localization.
- Simplified the status item presentation by removing the legacy icon and relying on text-only display.
