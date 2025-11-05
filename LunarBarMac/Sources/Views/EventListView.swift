//
//  EventListView.swift
//  LunarBarMac
//
//  Created for displaying event list below calendar grid.
//

import AppKit
import AppKitExtensions
import EventKit
import LunarBarKit

/**
 Event list view to show Calendar events for a selected date.
 */
final class EventListView: NSView {
  private let stackView = NSStackView()
  private let separatorView = NSBox()
  private var storedEvents: [EKCalendarItem] = []

  // Callback when an event is clicked
  var onEventClick: ((EKCalendarItem) -> Void)?

  override var intrinsicContentSize: NSSize {
    if isHidden || storedEvents.isEmpty {
      return NSSize(width: NSView.noIntrinsicMetric, height: 0)
    }
    let eventCount = storedEvents.count
    let height = Constants.topPadding + Constants.bottomPadding + Double(eventCount) * Constants.rowHeight + 1 + 4 // separator + top margin
    return NSSize(width: NSView.noIntrinsicMetric, height: height)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /**
   Update the event list with new events.
   If events is empty or all events are past, the entire view will be hidden.
   */
  func updateEvents(_ events: [EKCalendarItem]) {
    // Clear existing event rows
    stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

    // Filter out past events - only show upcoming events
    let upcomingEvents = events.filter { !isEventPast($0) }

    // Hide entire view if no upcoming events
    if upcomingEvents.isEmpty {
      isHidden = true
      Logger.log(.info, "EventListView.updateEvents: no upcoming events (total: \(events.count), past: \(events.count - upcomingEvents.count)), hiding view")
      return
    }

    isHidden = false
    Logger.log(.info, "EventListView.updateEvents: rendering \(upcomingEvents.count) upcoming events (filtered out \(events.count - upcomingEvents.count) past events)")

    // Add event rows (no maximum limit, fully adaptive)
    upcomingEvents.oldestToNewest.forEach { event in
      let eventRow = createEventRow(event: event)
      stackView.addArrangedSubview(eventRow)
      NSLayoutConstraint.activate([
        eventRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
        eventRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
      ])
    }
  }
}

// MARK: - Private

private extension EventListView {
  func setUp() {
    // Setup separator
    separatorView.boxType = .separator
    separatorView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(separatorView)

    // Setup stack view
    stackView.orientation = .vertical
    stackView.spacing = 0
    stackView.alignment = .leading
    stackView.distribution = .fillEqually
    stackView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stackView)

    let margin = AppDesign.contentMargin
    let spacing = AppDesign.dateCellSpacing
    let separatorInset = margin + spacing * 0.5 + 1  // Align with DateGrid cell content area
    NSLayoutConstraint.activate([
      // Separator at top aligned with cell content
      separatorView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: separatorInset),
      separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -separatorInset),
      separatorView.heightAnchor.constraint(equalToConstant: 1),

      // Stack view below separator
      stackView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: Constants.topPadding),
      stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.bottomPadding),
    ])
  }

  func createEventRow(event: EKCalendarItem) -> NSView {
    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false

    // Color dot
    let dotView = NSView()
    dotView.wantsLayer = true
    dotView.layer?.cornerRadius = Constants.dotSize / 2
    let color = event.calendar.color ?? Colors.controlAccent
    dotView.layer?.backgroundColor = color.cgColor
    dotView.layer?.borderColor = color.darkerColor().cgColor
    dotView.layer?.borderWidth = 0.5
    dotView.translatesAutoresizingMaskIntoConstraints = false

    // Event title
    let titleLabel = NSTextField(labelWithString: event.title)
    titleLabel.font = .systemFont(ofSize: Constants.fontSize)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    // Time label
    let timeLabel = NSTextField(labelWithString: event.labelOfDates)
    timeLabel.font = .systemFont(ofSize: Constants.fontSize)
    timeLabel.alignment = .right
    timeLabel.translatesAutoresizingMaskIntoConstraints = false

    containerView.addSubview(dotView)
    containerView.addSubview(titleLabel)
    containerView.addSubview(timeLabel)
    NSLayoutConstraint.activate([
      containerView.heightAnchor.constraint(equalToConstant: Constants.rowHeight),

      dotView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      dotView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
      dotView.widthAnchor.constraint(equalToConstant: Constants.dotSize),
      dotView.heightAnchor.constraint(equalToConstant: Constants.dotSize),

      titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: Constants.dotSpacing),
      titleLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

      timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Constants.labelSpacing),
      timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      timeLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
    ])

    // Add click handler
    let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleEventClick(_:)))
    containerView.addGestureRecognizer(clickGesture)

    // Store event reference in container
    containerView.identifier = NSUserInterfaceItemIdentifier(event.calendarItemIdentifier)

    // Add hover effect
    let trackingArea = NSTrackingArea(
      rect: containerView.bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: containerView,
      userInfo: nil
    )
    containerView.addTrackingArea(trackingArea)

    return containerView
  }

  func isEventPast(_ event: EKCalendarItem) -> Bool {
    let now = Date.now

    guard let endDate = event.endOfItem else {
      // No end time, use start time for判断
      guard let startDate = event.startOfItem else {
        return false
      }
      return startDate < now
    }

    // All-day event: compare dates (ignore specific time)
    if event.isAllDayItem {
      let todayStart = Calendar.solar.startOfDay(for: now)
      let eventEndDayStart = Calendar.solar.startOfDay(for: endDate)
      return eventEndDayStart < todayStart
    }

    // Timed event: directly compare timestamps
    return endDate < now
  }

  @objc func handleEventClick(_ gesture: NSClickGestureRecognizer) {
    guard let containerView = gesture.view,
          let identifier = containerView.identifier,
          let event = findEvent(byIdentifier: identifier.rawValue) else {
      return
    }

    // Trigger the callback with the found event
    onEventClick?(event)
  }

  // Helper to find event from stack view
  func findEvent(byIdentifier identifier: String) -> EKCalendarItem? {
    return storedEvents.first { $0.calendarItemIdentifier == identifier }
  }
}

// MARK: - Update with stored events

extension EventListView {
  func updateEventsWithStorage(_ events: [EKCalendarItem]) {
    // Filter out past events before storing
    let upcomingEvents = events.filter { !isEventPast($0) }
    storedEvents = upcomingEvents
    updateEvents(events)  // updateEvents will filter again internally
    invalidateIntrinsicContentSize()
    Logger.log(.info, "EventListView.updateEventsWithStorage: total=\(events.count) stored=\(upcomingEvents.count) height=\(self.intrinsicContentSize.height)")
  }
}

// MARK: - Extensions for date labels

private extension EKCalendarItem {
  var labelOfDates: String {
    guard !isAllDayItem else {
      return Localized.Calendar.allDayLabel
    }

    guard let startOfItem, let endOfItem else {
      Logger.assertFail("Missing start or end date")
      return ""
    }

    if startOfItem == endOfItem {
      return Constants.dateFormatter.string(from: startOfItem)
    }

    return "\(Constants.dateFormatter.string(from: startOfItem))–\(Constants.dateFormatter.string(from: endOfItem))"
  }
}

// MARK: - Constants

private enum Constants {
  static let fontSize: Double = 12.0
  static let dotSize: Double = 6
  static let rowHeight: Double = 28
  static let dotSpacing: Double = 8
  static let labelSpacing: Double = 16
  static let horizontalPadding: Double = 12
  static let topPadding: Double = 6
  static let bottomPadding: Double = 8
  static let maxHeight: Double = 200  // Maximum height for event list
  static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
}
