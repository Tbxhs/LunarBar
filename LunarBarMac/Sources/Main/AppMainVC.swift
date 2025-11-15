//
//  AppMainVC.swift
//  LunarBarMac
//
//  Created by cyan on 12/21/23.
//

import AppKit
import EventKit
import LunarBarKit

/**
 The main view controller that manages all components.
 */
final class AppMainVC: NSViewController {
  // States
  var monthDate = Date.now
  weak var popover: NSPopover?

  // Views
  private let scalableView = ScalableView()
  private let headerView = HeaderView()
  private let weekdayView = WeekdayView()
  private let dateGridView = DateGridView()
  private let eventListView = EventListView()

  // Factory function
  static func createPopover() -> NSPopover {
    let popover = NSPopover()
    popover.behavior = AppPreferences.General.pinnedOnTop ? .applicationDefined : .transient
    popover.contentSize = desiredContentSize
    popover.animates = !AppPreferences.Accessibility.reduceMotion

    let contentVC = Self()
    contentVC.popover = popover
    popover.contentViewController = contentVC

    return popover
  }
}

// MARK: - Internal

extension AppMainVC {
  override func loadView() {
    // Required prior to macOS Sonoma
    view = NSView(frame: CGRect(origin: .zero, size: Self.desiredContentSize))
    view.addScalableView(scalableView, scale: AppPreferences.General.contentScale.rawValue)
    Logger.log(.info, "AppMainVC.loadView finished")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setUp()
    observeKeyEvents()
    Logger.log(.info, "AppMainVC.viewDidLoad")
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    applyMaterial(AppPreferences.Accessibility.popoverMaterial)
    Logger.log(.info, "AppMainVC.viewWillAppear")

    updateAppearance()
    updateCalendar()

    // Select today after a short delay to ensure calendar is loaded
    Task {
      // Wait for calendar to load
      try? await Task.sleep(for: .milliseconds(100))

      let today = Date.now
      if Calendar.solar.month(from: monthDate) == Calendar.solar.month(from: today) {
        // Get today's events
        let startOfDay = Calendar.solar.startOfDay(for: today)
        let endOfDay = Calendar.solar.endOfDay(for: today)
        let events = try? await CalendarManager.default.items(from: startOfDay, to: endOfDay)
        let todayEvents = events?.filter {
          $0.overlaps(startOfDay: startOfDay, endOfDay: endOfDay)
        }.oldestToNewest ?? []

        // Select today and update event list
        await MainActor.run {
          dateGridView.selectDate(today)
          updateEventList(for: today, events: todayEvents)
        }
      }
    }
  }

  // MARK: - Updating

  func updateAppearance(_ appearance: Appearance = AppPreferences.General.appearance) {
    AppPreferences.General.appearance = appearance

    // Override both since in some contexts we don't have a window
    NSApp.appearance = appearance.resolved()
    view.window?.appearance = NSApp.appearance
  }

  func updateCalendar(targetDate: Date = .now) {
    Logger.log(.info, "Updating calendar to target date: \(targetDate)")
    monthDate = targetDate

    let solarYear = Calendar.solar.year(from: targetDate)
    let lunarInfo = LunarCalendar.default.info(of: solarYear)

    headerView.updateCalendar(date: targetDate)
    dateGridView.updateCalendar(date: targetDate, lunarInfo: lunarInfo)

    // Clear selection and event list, and resize popover to base size
    dateGridView.clearSelection()
    updateEventList(for: targetDate, events: [])
  }

  func updateCalendar(moveBy offset: Int, unit: Calendar.Component) {
    guard let newDate = Calendar.solar.date(byAdding: unit, value: offset, to: monthDate) else {
      return Logger.assertFail("Failed to get date by adding \(offset) \(unit)")
    }

    Logger.log(.info, "Moving the calendar by \(offset) \(unit)")
    updateCalendar(targetDate: newDate)
  }

  func gotoToday() {
    Logger.log(.info, "Going to today")
    let today = Date.now

    // Update calendar to today's month
    updateCalendar(targetDate: today)

    // Load today's events and select the date
    Task {
      let startOfDay = Calendar.solar.startOfDay(for: today)
      let endOfDay = Calendar.solar.endOfDay(for: today)
      let events = try? await CalendarManager.default.items(from: startOfDay, to: endOfDay)
      let todayEvents = events?.filter {
        $0.overlaps(startOfDay: startOfDay, endOfDay: endOfDay)
      }.oldestToNewest ?? []

      await MainActor.run {
        dateGridView.selectDate(today)
        updateEventList(for: today, events: todayEvents)
      }
    }
  }

  func togglePinnedOnTop() {
    AppPreferences.General.pinnedOnTop.toggle()
    popover?.behavior = AppPreferences.General.pinnedOnTop ? .applicationDefined : .transient
  }

  func updateEventList(for date: Date, events: [EKCalendarItem]) {
    eventListView.updateEventsWithStorage(events)

    // Update view and popover size to accommodate event list
    let baseSize = Self.desiredContentSize
    let eventListHeight = eventListView.intrinsicContentSize.height
    // Note: eventListHeight is in container's coordinate (unscaled), need to convert to display size
    let contentScale = AppPreferences.General.contentScale.rawValue
    let newSize = CGSize(width: baseSize.width, height: baseSize.height + eventListHeight * contentScale)

    // Use animation for smooth size transitions (unless user prefers reduced motion)
    if AppPreferences.Accessibility.reduceMotion {
      // No animation for users who prefer reduced motion
      view.setFrameSize(newSize)
      popover?.contentSize = newSize
    } else {
      // Smooth animation for size changes
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.35
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        view.animator().setFrameSize(newSize)
        popover?.contentSize = newSize
      }
    }

    Logger.log(.info, "updateEventList: events=\(events.count) height=\(eventListHeight)")
  }
}

// MARK: - HeaderViewDelegate

extension AppMainVC: HeaderViewDelegate {
  // periphery:ignore:parameters sender
  func headerView(_ sender: HeaderView, moveTo date: Date) {
    updateCalendar(targetDate: date)
  }

  // periphery:ignore:parameters sender
  func headerView(_ sender: HeaderView, moveBy offset: Int) {
    updateCalendar(moveBy: offset, unit: .month)
  }

  // periphery:ignore:parameters sender
  func headerViewGotoToday(_ sender: HeaderView) {
    gotoToday()
  }
}

// MARK: - Private

private extension AppMainVC {
  enum Constants {
    static let headerViewHeight: Double = 40
    static let weekdayViewHeight: Double = 17
    static let dateGridViewMarginTop: Double = 10
  }

  @MainActor static var desiredContentSize: CGSize {
    let cellInset = AppDesign.cellRectInset * 2
    let contentMargin = AppDesign.contentMargin * 2
    let contentScale = AppPreferences.General.contentScale.rawValue
    let cellSpacing = AppDesign.dateCellSpacing

    return CGSize(
      width: 240 * contentScale
        + cellInset * Double(Calendar.solar.numberOfDaysInWeek)
        + cellSpacing * Double(Calendar.solar.numberOfDaysInWeek - 1)
        + contentMargin,
      height: 320 * contentScale
        + cellInset * Double(Calendar.solar.numberOfRowsInMonth)
        + cellSpacing * Double(Calendar.solar.numberOfRowsInMonth - 1)
        + contentMargin
    )
  }

  func setUp() {
    let view = scalableView.container
    let margin = AppDesign.contentMargin

    headerView.delegate = self
    headerView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(headerView)

    // Set up date selection callback
    dateGridView.onDateSelected = { [weak self] date, events in
      Logger.log(.info, "Date selected: \(date) events=\(events.count)")
      self?.updateEventList(for: date, events: events)
    }

    // Set up event click callback
    eventListView.onEventClick = { event in
      (NSApp.delegate as? AppDelegate)?.openCalendar(targetDate: event.startOfItem ?? Date.now)
    }

    NSLayoutConstraint.activate([
      headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
      headerView.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
      headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
      headerView.heightAnchor.constraint(equalToConstant: Constants.headerViewHeight),
    ])

    weekdayView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(weekdayView)
    NSLayoutConstraint.activate([
      weekdayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
      weekdayView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
      weekdayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
      weekdayView.heightAnchor.constraint(equalToConstant: Constants.weekdayViewHeight),
    ])

    dateGridView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(dateGridView)

    eventListView.translatesAutoresizingMaskIntoConstraints = false
    eventListView.isHidden = true
    view.addSubview(eventListView)

    // Calculate fixed height for dateGridView to maintain its size
    // Note: ScalableView's container size is desiredContentSize / contentScale
    let contentScale = AppPreferences.General.contentScale.rawValue
    let actualContainerHeight = Self.desiredContentSize.height / contentScale
    let dateGridHeight = actualContainerHeight - margin - Constants.headerViewHeight - Constants.weekdayViewHeight - Constants.dateGridViewMarginTop - margin

    NSLayoutConstraint.activate([
      // Date grid view with fixed height to maintain original size
      dateGridView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
      dateGridView.topAnchor.constraint(equalTo: weekdayView.bottomAnchor, constant: Constants.dateGridViewMarginTop),
      dateGridView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
      dateGridView.heightAnchor.constraint(equalToConstant: dateGridHeight),

      // Event list view positioned directly below date grid (no spacing)
      eventListView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
      eventListView.topAnchor.constraint(equalTo: dateGridView.bottomAnchor, constant: 0),
      eventListView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
    ])
  }

  func observeKeyEvents() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.view.window?.isKeyWindow == true else {
        return event
      }

      switch event.keyCode {
      case .kVK_Escape:
        if self.dateGridView.cancelHighlight() {
          return nil
        }

        return event
      case .kVK_LeftArrow:
        self.updateCalendar(moveBy: -1, unit: .month)
        self.headerView.showClickEffect(for: .previous)
        return nil
      case .kVK_RightArrow:
        self.updateCalendar(moveBy: 1, unit: .month)
        self.headerView.showClickEffect(for: .next)
        return nil
      case .kVK_UpArrow:
        self.updateCalendar(moveBy: -1, unit: .year)
        return nil
      case .kVK_DownArrow:
        self.updateCalendar(moveBy: 1, unit: .year)
        return nil
      case .kVK_ANSI_P:
        self.togglePinnedOnTop()
        return nil
      default:
        return event
      }
    }
  }
}
