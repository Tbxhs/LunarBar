//
//  AppDelegate.swift
//  LunarBarMac
//
//  Created by cyan on 12/21/23.
//

import AppKit
import LunarBarKit
#if canImport(Sparkle)
import Sparkle
#endif

class AppDelegate: NSObject, NSApplicationDelegate {
  private lazy var statusItem: NSStatusItem = {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.autosaveName = Bundle.main.bundleName
    item.behavior = .terminationOnRemoval

    return item
  }()

  private weak var presentedPopover: NSPopover?
  private var dateRefreshTimer: DateRefreshTimer?
  private var popoverClosedTime: TimeInterval = 0
  private var countingDate: Date?

#if canImport(Sparkle)
  private var sparkleController: SPUStandardUpdaterController?
#endif

  func applicationDidFinishLaunching(_ notification: Notification) {
    Logger.log(.info, "applicationDidFinishLaunching: start")
    // We rely on tooltips to display information, change the initial delay to 1s to be faster
    UserDefaults.standard.setValue(1000, forKey: "NSInitialToolTipDelay")
    Logger.log(.info, "Tooltip delay configured")

    // Prepare public holiday data
    _ = HolidayManager.default
    Logger.log(.info, "Holiday manager initialized")

#if canImport(Sparkle)
    // Initialize Sparkle updater on the main thread before any checkForUpdates call.
    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    sparkleController = controller
    AppUpdater.configureSparkleController(controller)
    Logger.log(.info, "Sparkle updater configured")
#endif

    // Update the icon and attach it to the menu bar
    updateMenuBarIcon()
    statusItem.isVisible = true
    Logger.log(.info, "Status item visible: \(self.statusItem.isVisible)")

    // Repeated refresh based on the date format granularity
    dateRefreshTimer = DateRefreshTimer { [weak self] in self?.updateMenuBarIcon() }
    updateDateRefreshTimer()
    Logger.log(.info, "Date refresh timer configured")

    // Observe events that do not require a specific window
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == .kVK_ANSI_Q && event.deviceIndependentFlags == .command {
        NSApp.terminate(nil)
        return nil
      }

      if event.keyCode == .kVK_ANSI_W && event.deviceIndependentFlags == .command {
        event.window?.close()
        return nil
      }

      return event
    }

    // We don't rely on the button's target-action,
    // because we want to keep the button highlighted when the popover is shown.
    NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      if let self, self.shouldOpenPanel(for: event) {
        self.openPanel()
        return nil
      }

      return event
    }

    // Handle right-click to show context menu
    NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
      guard let self else {
        return event
      }

      if event.window == self.statusItem.button?.window {
        self.showContextMenu()
        return nil
      }

      return event
    }

    // Observe clicks outside the app
    NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
      guard let popover = self?.presentedPopover else {
        return
      }

      // When the app is activated, clicking on other status items would not always close ours
      if popover.isShown && popover.behavior != .applicationDefined {
        popover.close()
      }
    }

    Logger.log(.info, "Requesting calendar access and preload")
    Task {
      await CalendarManager.default.requestAccessIfNeeded(type: .event)
      await CalendarManager.default.preload(date: .now)
      Logger.log(.info, "Calendar preload finished")

      // We don't even have a main window, open the panel for initial launch
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        guard AppPreferences.General.initialLaunch else {
          Logger.log(.info, "Initial launch already handled")
          return
        }

        Logger.log(.info, "Initial launch: opening panel")
        self.openPanel()
        AppPreferences.General.initialLaunch = false
      }
    }

    let silentlyCheckUpdates: @Sendable () -> Void = {
      Task {
        await AppUpdater.checkForUpdates(explicitly: false)
      }

      Task {
        await HolidayManager.default.fetchDefaultHolidays()
      }
    }

    Logger.log(.info, "Scheduling update checks")
    // Check for updates on launch with a delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: silentlyCheckUpdates)

    // Check for updates on a weekly basis, for users who never quit apps
    Timer.scheduledTimer(withTimeInterval: 7 * 24 * 60 * 60, repeats: true) { _ in
      silentlyCheckUpdates()
    }
    Logger.log(.info, "applicationDidFinishLaunching: observers registering")

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(calendarDayDidChange(_:)),
      name: .NSCalendarDayChanged,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidUpdate(_:)),
      name: NSWindow.didUpdateNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResignKey(_:)),
      name: NSWindow.didResignKeyNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(menuBarIconDidChange(_:)),
      name: .menuBarIconDidChange,
      object: nil
    )
    Logger.log(.info, "applicationDidFinishLaunching: finished")
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // These events are sent whenever the Finder reactivates an already running application because someone double-clicked it again or used the dock to activate it.
    openPanel()
    return false
  }

  @MainActor
  func updateMenuBarIcon(needsLayout: Bool = false) {
    // Clear all content
    statusItem.button?.title = ""
    statusItem.button?.image = nil

    // Select display mode based on user configuration
    switch AppPreferences.General.menuBarIcon {
    case .filledDate:
      if let image = AppIconFactory.createDateIcon(style: .filled) {
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
      }

    case .outlinedDate:
      if let image = AppIconFactory.createDateIcon(style: .outlined) {
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
      }

    case .calendar:
      if let image = AppIconFactory.createCalendarIcon() {
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
      }

    case .systemSymbol:
      if let image = AppIconFactory.createSystemIcon() {
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
      }

    case .custom:
      if let image = AppIconFactory.createCustomIcon() {
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
      } else {
        // If custom format is invalid, show default text
        updateTitleOnly()
      }
    }

    // Set accessibility label
    let accessibilityLabel = getAccessibilityLabel()
    statusItem.button?.setAccessibilityLabel(accessibilityLabel)

    // The popover position will be slightly moved without this trick
    if needsLayout {
      presentedPopover?.close()
      statusItem.button?.superview?.needsLayout = true
    }

    updateTooltip()
  }

  @MainActor
  private func updateTitleOnly() {
    // Fallback display mode: text only (localized)
    let dateFormatter = DateFormatter()
    dateFormatter.setLocalizedDateFormatFromTemplate("MMMd EEE")
    let dateText = dateFormatter.string(from: Date.now)
    statusItem.button?.title = dateText
  }

  @MainActor
  private func getAccessibilityLabel() -> String {
    return getFormattedDateString()
  }

  @MainActor
  private func getFormattedDateString() -> String {
    return DateFormatter.fullDate.string(from: Date.now)
  }

  @MainActor
  func updateDateRefreshTimer() {
    if AppPreferences.General.menuBarIcon == .custom {
      dateRefreshTimer?.dateFormat = AppPreferences.General.customDateFormat
    } else {
      dateRefreshTimer?.dateFormat = nil
    }
  }

  @MainActor
  func updateTooltip() {
    let currentDate = Date.now
    statusItem.button?.toolTip = [
      getFormattedDateString(),
      DateFormatter.lunarDate.string(from: currentDate).removingLeadingDigits,
    ].joined(separator: "\n\n")
  }

  @MainActor
  func openPanel() {
    guard let sender = statusItem.button else {
      return Logger.assertFail("Missing source view to proceed")
    }
    Logger.log(.info, "openPanel: presenting popover")

    let popover = AppMainVC.createPopover()
    popover.delegate = self
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    presentedPopover = popover

    // Ensure the app is activated and the window is key and ordered front
    NSApp.activate(ignoringOtherApps: true)
    popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    Logger.log(.info, "openPanel: popover shown")

    // Keep the button highlighted to mimic the system behavior
    sender.highlight(true)

    // Clear the tooltip to prevent overlap
    sender.toolTip = nil
  }

  @MainActor
  func openCalendar(targetDate: Date) {
    guard presentedPopover?.isShown == true else {
      return
    }

    // Clear states and open the Calendar app
    presentedPopover?.close()
    CalendarManager.default.revealDateInCalendar(targetDate)
  }

  @MainActor
  func countDaysBetween(targetDate: Date) {
    guard let startDate = countingDate, targetDate != startDate else {
      countingDate = targetDate
      return
    }

    guard let daysBetween = Calendar.solar.daysBetween(from: startDate, to: targetDate) else {
      countingDate = nil
      return
    }

    countingDate = nil
    presentedPopover?.close()

    let alert = NSAlert()
    alert.messageText = String(
      format: Localized.Calendar.daysBetweenTemplate,
      DateFormatter.mediumDate.string(from: min(startDate, targetDate)),
      DateFormatter.mediumDate.string(from: max(startDate, targetDate)),
      abs(daysBetween)
    )

    alert.runModal()
  }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
  func popoverWillClose(_ notification: Notification) {
    popoverClosedTime = Date.timeIntervalSinceReferenceDate
    countingDate = nil
  }
}

// MARK: - Private

@MainActor
private extension AppDelegate {
  // periphery:ignore:parameters notification
  @objc func calendarDayDidChange(_ notification: Notification) {
    DispatchQueue.main.async {
      self.updateMenuBarIcon()
    }
  }

  // periphery:ignore:parameters notification
  @objc func windowDidUpdate(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window.className == "NSToolTipPanel" else {
      return
    }

    guard presentedPopover == nil else {
      return
    }

    // Tooltip from the status bar sometimes has incorrect appearance
    window.appearance = NSApp.effectiveAppearance
  }

  // periphery:ignore:parameters notification
  @objc func windowDidResignKey(_ notification: Notification) {
    guard (notification.object as? NSWindow)?.contentViewController is AppMainVC else {
      return
    }

    // Cancel the highlight when the popover window is no longer the key window
    statusItem.button?.highlight(false)
    updateTooltip()
  }

  // periphery:ignore:parameters notification
  @objc func menuBarIconDidChange(_ notification: Notification) {
    updateMenuBarIcon()
  }

  func shouldOpenPanel(for event: NSEvent) -> Bool {
    guard event.window == statusItem.button?.window else {
      // The click was outside the status window
      return false
    }

    guard !event.modifierFlags.contains(.command) else {
      // Holding the command key usually means the icon is being dragged
      return false
    }

    // Measure the absolute value, taking system clock or time zone changes into account
    guard abs(Date.timeIntervalSinceReferenceDate - popoverClosedTime) > 0.1 else {
      // The click was to close the popover
      return false
    }

    // Prevent multiple popovers, e.g., when pin on top is enabled
    if let popover = presentedPopover, popover.isShown {
      // Just think of it as a "pin on top" cancellation
      popover.behavior = .transient
      popover.close()
      return false
    }

    return true
  }

  func showContextMenu() {
    guard let button = statusItem.button else {
      return
    }

    // Create a temporary AppMainVC to access its menu creation methods
    let tempVC = AppMainVC.createPopover().contentViewController as? AppMainVC
    guard let vc = tempVC else {
      Logger.assertFail("Failed to create temporary AppMainVC for context menu")
      return
    }

    // Create the simplified context menu with 5 top-level items
    let menu = NSMenu()
    menu.addItem(vc.menuItemMenuBarIcon)
    menu.addItem(vc.menuItemAppearance)
    menu.addItem(vc.menuItemCalendars)
    menu.addItem(vc.menuItemLaunchAtLogin)
    menu.addSeparator()
    menu.addItem(vc.menuItemAboutAndHelp)
    menu.addSeparator()
    menu.addItem(vc.menuItemQuitLunarBar)

    // Show the menu
    statusItem.menu = menu
    button.performClick(nil)
    statusItem.menu = nil
  }
}
