//
//  AppMainVC+Menu.swift
//  LunarBarMac
//
//  Created by cyan on 12/28/23.
//

import AppKit
import AppKitControls
import AppKitExtensions
import LunarBarKit
import ServiceManagement

// MARK: - Internal

extension AppMainVC {
  enum MenuConstants {
    @MainActor static let menuIconSize: Double = AppDesign.menuIconSize
  }

  // MARK: - Flattened Menu Items

  var menuItemMenuBarIcon: NSMenuItem {
    let menu = NSMenu()

    // Filled Date
    menu.addItem(createDateIconItem(
      style: .filled,
      title: Localized.UI.menuTitleFilledDate,
      isOn: AppPreferences.General.menuBarIcon == .filledDate,
      action: AppPreferences.General.menuBarIcon = .filledDate
    ))

    // Outlined Date
    menu.addItem(createDateIconItem(
      style: .outlined,
      title: Localized.UI.menuTitleOutlinedDate,
      isOn: AppPreferences.General.menuBarIcon == .outlinedDate,
      action: AppPreferences.General.menuBarIcon = .outlinedDate
    ))

    // Calendar Icon
    menu.addItem({
      let item = NSMenuItem(title: Localized.UI.menuTitleCalendarIcon)
      item.image = AppIconFactory.createCalendarIcon(pointSize: MenuConstants.menuIconSize)
      item.setOn(AppPreferences.General.menuBarIcon == .calendar)
      item.addAction {
        AppPreferences.General.menuBarIcon = .calendar
      }
      return item
    }())

    menu.addSeparator()

    // System Symbol
    menu.addItem(createCustomIconItem(
      item: {
        let item = NSMenuItem(title: Localized.UI.menuTitleSystemSymbol)
        item.image = .with(symbolName: Icons.gear, pointSize: MenuConstants.menuIconSize)
        item.setOn(AppPreferences.General.menuBarIcon == .systemSymbol)
        return item
      }(),
      alert: {
        let alert = NSAlert()
        alert.messageText = Localized.UI.alertMessageSetSymbolName
        alert.addButton(withTitle: Localized.UI.alertButtonTitleApplyChanges)
        alert.addButton(withTitle: Localized.General.cancel)
        return alert
      }(),
      explanation: Localized.UI.alertExplanationSetSymbolName,
      initialValue: AppPreferences.General.systemSymbolName
    ) { symbolName in
      guard NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil else {
        return false
      }
      AppPreferences.General.systemSymbolName = symbolName
      AppPreferences.General.menuBarIcon = .systemSymbol
      return true
    })

    // Custom Format
    menu.addItem(createCustomIconItem(
      item: {
        let item = NSMenuItem(title: Localized.UI.menuTitleCustomFormat)
        item.image = .with(symbolName: Icons.wandAndSparkles, pointSize: MenuConstants.menuIconSize)
        item.setOn(AppPreferences.General.menuBarIcon == .custom)
        return item
      }(),
      alert: {
        let alert = NSAlert()
        alert.messageText = Localized.UI.alertMessageSetDateFormat
        alert.addButton(withTitle: Localized.UI.alertButtonTitleApplyChanges)
        alert.addButton(withTitle: Localized.General.cancel)
        return alert
      }(),
      explanation: Localized.UI.alertExplanationSetDateFormat,
      initialValue: AppPreferences.General.customDateFormat
    ) { dateFormat in
      guard !dateFormat.isEmpty else {
        return false
      }
      AppPreferences.General.customDateFormat = dateFormat
      AppPreferences.General.menuBarIcon = .custom
      return true
    })

    let item = NSMenuItem(title: Localized.UI.menuTitleMenuBarIcon)
    item.submenu = menu
    return item
  }

  var menuItemAppearance: NSMenuItem {
    let menu = NSMenu()

    // Color Scheme
    menu.addItem(withTitle: Localized.UI.menuTitleColorScheme).isEnabled = false
    [
      (Localized.UI.menuTitleSystem, Appearance.system),
      (Localized.UI.menuTitleLight, Appearance.light),
      (Localized.UI.menuTitleDark, Appearance.dark),
    ].forEach { (title: String, appearance: Appearance) in
      menu.addItem(withTitle: title) { [weak self] in
        self?.updateAppearance(appearance)
      }
      .setOn(AppPreferences.General.appearance == appearance)
    }

    menu.addSeparator()

    // Content Scale
    menu.addItem(withTitle: Localized.UI.menuTitleContentScale).isEnabled = false
    [
      (Localized.UI.menuTitleScaleDefault, ContentScale.default),
      (Localized.UI.menuTitleScaleRoomy, ContentScale.roomy),
    ].forEach { (title: String, scale: ContentScale) in
      menu.addItem(withTitle: title) { [weak self] in
        AppPreferences.General.contentScale = scale
        self?.closePopover()

        if let delegate = NSApp.delegate as? AppDelegate {
          delegate.openPanel()
        } else {
          Logger.assertFail("Unexpected app delegate: \(String(describing: NSApp.delegate))")
        }
      }
      .setOn(AppPreferences.General.contentScale == scale)
    }

    menu.addSeparator()

    // Pin on Top
    menu.addItem(withTitle: Localized.UI.menuTitlePinOnTop) { [weak self] in
      self?.togglePinnedOnTop()
    }
    .setOn(AppPreferences.General.pinnedOnTop)

    let item = NSMenuItem(title: Localized.UI.menuTitleAppearance)
    item.submenu = menu
    return item
  }

  var menuItemCalendars: NSMenuItem {
    let menu = NSMenu()
    menu.autoenablesItems = false

    let calendars = CalendarManager.default.allCalendars()
    let remindersIndex = calendars.firstIndex { $0.allowedEntityTypes.contains(.reminder) }
    let identifiers = Set(calendars.map { $0.calendarIdentifier })

    for (index, calendar) in calendars.enumerated() {
      let calendarID = calendar.calendarIdentifier
      let item = NSMenuItem(title: calendar.title)
      item.setOn(!AppPreferences.Calendar.hiddenCalendars.contains(calendarID))

      item.addAction { [weak self] in
        AppPreferences.Calendar.hiddenCalendars.toggle(calendarID)
        self?.reloadCalendar()
      }

      if let color = calendar.color {
        item.image = .with(
          cellColor: color,
          borderColor: color.darkerColor(),
          borderWidth: view.hairlineWidth,
          size: CGSize(width: 12, height: 12),
          cornerRadius: 3
        )
      }

      if remindersIndex == index {
        menu.addItem(.separator())
      }

      item.isEnabled = true
      menu.addItem(item)
    }

    menu.addSeparator()

    if CalendarManager.default.authorizationStatus(for: .reminder) == .notDetermined {
      menu.addItem(withTitle: Localized.UI.menuTitleShowReminders) {
        Task {
          await CalendarManager.default.requestAccessIfNeeded(type: .reminder)
        }
      }
      menu.addSeparator()
    }

    menu.addItem(withTitle: Localized.UI.menuTitleSelectAll) { [weak self] in
      AppPreferences.Calendar.hiddenCalendars.removeAll()
      self?.reloadCalendar()
    }.isEnabled = !AppPreferences.Calendar.hiddenCalendars.isEmpty

    menu.addItem(withTitle: Localized.UI.menuTitleDeselectAll) { [weak self] in
      AppPreferences.Calendar.hiddenCalendars = identifiers
      self?.reloadCalendar()
    }.isEnabled = AppPreferences.Calendar.hiddenCalendars != identifiers

    menu.addSeparator()
    menu.addItem(withTitle: Localized.UI.menuTitlePrivacySettings) { [weak self] in
      self?.closePopover()
      NSWorkspace.shared.safelyOpenURL(string: "x-apple.systempreferences:com.apple.preference.security")
    }

    let item = NSMenuItem(title: Localized.UI.menuTitleCalendars)
    item.submenu = menu
    return item
  }

  var menuItemPublicHolidays: NSMenuItem {
    let menu = NSMenu()
    menu.addItem(withTitle: Localized.UI.menuTitleDefaultHolidays) { [weak self] in
      AppPreferences.Calendar.defaultHolidays.toggle()
      self?.reloadCalendar()
    }
    .setOn(AppPreferences.Calendar.defaultHolidays)

    menu.addItem(withTitle: Localized.UI.menuTitleFetchUpdates) { [weak self] in
      Task {
        await HolidayManager.default.fetchDefaultHolidays()
        self?.reloadCalendar()
      }
    }

    menu.addSeparator()

    // User defined, read-only here
    HolidayManager.default.userDefinedFiles.forEach {
      let item = NSMenuItem(title: $0)
      item.isEnabled = false
      item.setOn(true)
      menu.addItem(item)
    }

    menu.addSeparator()

    menu.addItem(withTitle: Localized.UI.menuTitleOpenDirectory) { [weak self] in
      self?.closePopover()
      HolidayManager.default.openUserDefinedDirectory()
    }

    menu.addItem(withTitle: Localized.UI.menuTitleCustomizationTips) { [weak self] in
      self?.closePopover()
      NSWorkspace.shared.safelyOpenURL(string: "https://github.com/Tbxhs/Holidays")
    }

    menu.addSeparator()

    menu.addItem(withTitle: Localized.UI.menuTitleReloadCustomizations) { [weak self] in
      HolidayManager.default.reloadUserDefinedFiles()
      self?.reloadCalendar()
    }

    let item = NSMenuItem(title: Localized.UI.menuTitlePublicHolidays)
    item.submenu = menu
    return item
  }

  var menuItemLaunchAtLogin: NSMenuItem {
    let item = NSMenuItem(title: Localized.UI.menuTitleLaunchAtLogin)
    item.setOn(SMAppService.mainApp.isEnabled)

    item.addAction {
      do {
        try SMAppService.mainApp.toggle()
      } catch {
        Logger.log(.error, error.localizedDescription)
      }
    }

    return item
  }

  var menuItemAboutLunarBar: NSMenuItem {
    let item = NSMenuItem(title: Localized.UI.menuTitleAboutLunarBar)
    item.addAction { [weak self] in
      self?.closePopover()
      NSApp.activate(ignoringOtherApps: true)
      NSApp.orderFrontStandardAboutPanel(nil)
    }

    return item
  }

  var menuItemGitHub: NSMenuItem {
    let item = NSMenuItem(title: Localized.UI.menuTitleGitHub)
    item.addAction { [weak self] in
      self?.closePopover()
      NSWorkspace.shared.safelyOpenURL(string: "https://github.com/Tbxhs/LunarBar")
    }

    return item
  }

  var menuItemCheckForUpdates: NSMenuItem {
    let item = NSMenuItem(title: Localized.UI.menuTitleCheckForUpdates)
    item.addAction { [weak self] in
      Task {
        self?.closePopover()
        await AppUpdater.checkForUpdates(explicitly: true)
      }
    }

    return item
  }

  var menuItemQuitLunarBar: NSMenuItem {
    let item = NSMenuItem(title: Localized.UI.menuTitleQuitLunarBar, action: nil, keyEquivalent: "q")
    item.keyEquivalentModifierMask = .command
    item.addAction {
      NSApp.terminate(nil)
    }

    return item
  }

  var menuItemAboutAndHelp: NSMenuItem {
    let menu = NSMenu()

    menu.addItem(menuItemAboutLunarBar)
    menu.addItem(menuItemGitHub)

    menu.addSeparator()

    menu.addItem(menuItemCheckForUpdates)

    let item = NSMenuItem(title: Localized.UI.menuTitleAboutAndHelp)
    item.submenu = menu
    return item
  }

  // MARK: - Helper Methods

  func createDateIconItem(
    style: DateIconStyle,
    title: String,
    isOn: Bool,
    action: @autoclosure @escaping () -> Void
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title)
    item.setOn(isOn)
    item.addAction(action)

    if let image = AppIconFactory.createDateIcon(style: style) {
      item.image = image.resized(with: CGSize(width: 16.8, height: 12)) // 1.4:1
    } else {
      Logger.assertFail("Failed to create the icon")
    }

    return item
  }

  func createCustomIconItem(
    item: NSMenuItem,
    alert: NSAlert,
    explanation: String,
    initialValue: String?,
    commitChange: @escaping (String) -> Bool
  ) -> NSMenuItem {
    let inputField = EditableTextField(frame: CGRect(x: 0, y: 0, width: 256, height: 22))
    inputField.cell?.usesSingleLineMode = true
    inputField.cell?.lineBreakMode = .byTruncatingTail
    inputField.stringValue = initialValue ?? ""

    let textView = NSTextView.markdownView(
      with: explanation,
      contentWidth: inputField.frame.width
    )

    textView.frame = CGRect(
      origin: CGPoint(x: 0, y: inputField.frame.height + 15), // Spacing between two fields
      size: textView.frame.size
    )

    let wrapper = NSView(frame: {
      var rect = textView.frame
      rect.size.height += textView.frame.minY // Text view height and the spacing
      return rect
    }())

    wrapper.addSubview(textView)
    wrapper.addSubview(inputField)
    alert.accessoryView = wrapper
    alert.layout()

    func showAlert() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        inputField.window?.makeFirstResponder(inputField)
      }

      guard alert.runModal() == .alertFirstButtonReturn else {
        return
      }

      guard !commitChange(inputField.stringValue) else {
        return
      }

      // Failed to commit the change
      NSSound.beep()
      showAlert()
    }

    item.addAction(showAlert)
    return item
  }

  func reloadCalendar() {
    updateCalendar(targetDate: monthDate)
  }

  func closePopover() {
    popover?.close()
  }
}
