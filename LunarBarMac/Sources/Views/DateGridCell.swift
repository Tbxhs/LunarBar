//
//  DateGridCell.swift
//  LunarBarMac
//
//  Created by cyan on 12/22/23.
//

import AppKit
import AppKitControls
import EventKit
import LunarBarKit

/**
 Grid cell that draws a day, including its solar date and lunar date and decorating views.

 Example: 22 初十
 */
final class DateGridCell: NSCollectionViewItem {
  static let reuseIdentifier = NSUserInterfaceItemIdentifier("DateGridCell")

  private(set) var cellDate: Date?
  private var cellEvents = [EKCalendarItem]()
  private var mainInfo = ""
  private var isDateSelected = false

  private var detailsTask: Task<Void, Never>?
  private weak var detailsPopover: NSPopover?

  // Callback when the cell is clicked to select the date
  var onDateSelected: ((Date, [EKCalendarItem]) -> Void)?

  private let containerView: CustomButton = {
    let button = CustomButton()
    button.setAccessibilityElement(true)
    button.setAccessibilityRole(.button)
    button.setAccessibilityHelp(Localized.UI.accessibilityClickToRevealDate)

    return button
  }()

  private let highlightView: NSView = {
    let view = NSView()
    view.wantsLayer = true
    view.alphaValue = 0

    view.layer?.cornerRadius = AppDesign.cellCornerRadius
    view.layer?.cornerCurve = .continuous

    return view
  }()

  private let solarLabel: TextLabel = {
    let label = TextLabel()
    label.textColor = Colors.primaryLabel
    label.font = .mediumSystemFont(ofSize: Constants.solarFontSize)
    label.setAccessibilityHidden(true)

    return label
  }()

  private let lunarLabel: TextLabel = {
    let label = TextLabel()
    label.textColor = Colors.primaryLabel
    label.font = .mediumSystemFont(ofSize: Constants.lunarFontSize)
    label.setAccessibilityHidden(true)

    return label
  }()

  private let eventView: EventView = {
    let view = EventView()
    view.setAccessibilityHidden(true)

    return view
  }()

  private let focusRingView: NSView = {
    let view = NSView()
    view.wantsLayer = true
    view.isHidden = true
    view.setAccessibilityHidden(true)

    view.layer?.borderWidth = Constants.focusRingBorderWidth
    view.layer?.cornerRadius = AppDesign.cellCornerRadius
    view.layer?.cornerCurve = .continuous

    return view
  }()

  private let selectionRingView: NSView = {
    let view = NSView()
    view.wantsLayer = true
    view.isHidden = true
    view.setAccessibilityHidden(true)

    view.layer?.borderWidth = Constants.selectionRingBorderWidth
    view.layer?.borderColor = NSColor.systemGreen.cgColor
    view.layer?.cornerRadius = AppDesign.cellCornerRadius
    view.layer?.cornerCurve = .continuous
    view.layer?.backgroundColor = NSColor.clear.cgColor

    return view
  }()

  private let holidayView: NSImageView = {
    let view = NSImageView(image: Constants.holidayViewImage)
    view.isHidden = true
    view.setAccessibilityHidden(true)

    return view
  }()
}

// MARK: - Life Cycle

extension DateGridCell {
  override func loadView() {
    // Required prior to macOS Sonoma
    view = NSView(frame: .zero)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setUp()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    containerView.frame = view.bounds

    highlightView.layerBackgroundColor = .highlightedBackground

    // 设置今日标记为绿色圆形背景
    focusRingView.layer?.backgroundColor = NSColor.systemGreen.cgColor
    focusRingView.layer?.borderWidth = 0  // 移除边框

    // 根据 focusRingView 的实际尺寸设置圆角，让它变成圆形或近似圆形
    let size = focusRingView.bounds.size
    let radius = min(size.width, size.height) / 2
    focusRingView.layer?.cornerRadius = radius

    // 设置选中标记为空心圆圈
    let selectionSize = selectionRingView.bounds.size
    let selectionRadius = min(selectionSize.width, selectionSize.height) / 2
    selectionRingView.layer?.cornerRadius = selectionRadius
  }
}

// MARK: - Updating

extension DateGridCell {
  func updateViews(
    cellDate: Date,
    cellEvents: [EKCalendarItem],
    monthDate: Date?,
    lunarInfo: LunarInfo?
  ) {
    self.cellDate = cellDate
    self.cellEvents = cellEvents

    let currentDate = Date.now
    let solarComponents = Calendar.solar.dateComponents([.year, .month, .day], from: cellDate)
    let lunarComponents = Calendar.lunar.dateComponents([.year, .month, .day], from: cellDate)
    let lastDayOfLunarYear = Calendar.lunar.lastDayOfYear(from: cellDate)
    let isLeapLunarMonth = Calendar.lunar.isLeapMonth(from: cellDate)

    let solarMonthDay = solarComponents.fourDigitsMonthDay
    let lunarMonthDay = lunarComponents.fourDigitsMonthDay

    let holidayType = HolidayManager.default.typeOf(
      year: solarComponents.year ?? 0, // It's too broken to have year as nil
      monthDay: solarMonthDay
    )

    // Solar day label
    if let day = solarComponents.day {
      solarLabel.stringValue = String(day)
    } else {
      Logger.assertFail("Failed to get solar day from date: \(cellDate)")
    }

    // Lunar day label
    if let day = lunarComponents.day {
      if day == 1, let month = lunarComponents.month {
        // The Chinese character "月" will shift the layout slightly to the left,
        // add a "thin space" to make it optically centered.
        lunarLabel.stringValue = "\u{2009}" + AppLocalizer.chineseMonth(of: month - 1, isLeap: isLeapLunarMonth)
      } else {
        lunarLabel.stringValue = AppLocalizer.chineseDay(of: day - 1)
      }
    } else {
      Logger.assertFail("Failed to get lunar day from date: \(cellDate)")
    }

    // Prefer solar term over normal lunar day
    if let solarTerm = lunarInfo?.solarTerms[solarMonthDay] {
      lunarLabel.stringValue = AppLocalizer.solarTerm(of: solarTerm)
    }

    // Prefer lunar holiday over solar term
    if let lunarHoliday = AppLocalizer.lunarFestival(of: lunarMonthDay) {
      lunarLabel.stringValue = lunarHoliday
    }

    // Chinese New Year's Eve, the last day of the lunar year, not necessarily a certain date
    if let lastDayOfLunarYear, Calendar.lunar.isDate(cellDate, inSameDayAs: lastDayOfLunarYear) {
      lunarLabel.stringValue = Localized.Calendar.chineseNewYearsEve
    }

    // Show the focus ring only for today
    let isDateToday = Calendar.solar.isDate(cellDate, inSameDayAs: currentDate)
    focusRingView.isHidden = !isDateToday

    // Show selection ring for selected non-today dates
    selectionRingView.isHidden = !(isDateSelected && !isDateToday)

    // 当是今天时，文字显示为白色
    if isDateToday {
      solarLabel.textColor = .white
      lunarLabel.textColor = .white
    } else {
      solarLabel.textColor = Colors.primaryLabel
      lunarLabel.textColor = Colors.primaryLabel
    }

    // Reload event dot views
    eventView.updateEvents(cellEvents)

    // Bookmark for holiday plans
    switch holidayType {
    case .none:
      holidayView.isHidden = true
      holidayView.contentTintColor = nil
    case .workday:
      holidayView.isHidden = false
      holidayView.contentTintColor = .systemRed  // 上班日用红色
    case .holiday:
      holidayView.isHidden = false
      holidayView.contentTintColor = .systemGreen  // 休假日用绿色
    }

    self.mainInfo = {
      var components: [String] = []
      // E.g. [Holiday]
      if let holidayLabel = AppLocalizer.holidayLabel(of: holidayType) {
        components.append(holidayLabel)
      }

      // Formatted lunar date, e.g., 癸卯年冬月十五 (leading numbers are removed to be concise)
      let lunarDate = Constants.lunarDateFormatter.string(from: cellDate)
      components.append(lunarDate.removingLeadingDigits)

      // Date ruler, e.g., "(10 days ago)" when hovering over a cell
      if let daysBetween = Calendar.solar.daysBetween(from: currentDate, to: cellDate) {
        if daysBetween == 0 {
          components.append(Localized.Calendar.todayLabel)
        } else {
          let format = daysBetween > 0 ? Localized.Calendar.daysLaterFormat : Localized.Calendar.daysAgoFormat
          components.append(String.localizedStringWithFormat(format, abs(daysBetween)))
        }
      }

      return components.joined()
    }()

    let accessibleDetails = {
      let eventTitles = cellEvents.compactMap { $0.title }

      // Only the main info
      if eventTitles.isEmpty {
        return mainInfo
      }

      // Full version, each trailing line is an event title
      return [mainInfo, eventTitles.joined(separator: "\n")].joined(separator: "\n\n")
    }()

    // Combine all visually available information to get the accessibility label
    containerView.setAccessibilityLabel([
      solarLabel.stringValue,
      lunarLabel.stringValue,
      accessibleDetails,
    ].compactMap { $0 }.joined(separator: " "))
  }

  func updateOpacity(monthDate: Date?) {
    let currentDate = Date.now
    let cellDate = cellDate ?? currentDate

    let solarComponents = Calendar.solar.dateComponents([.month], from: cellDate)
    let isDateToday = Calendar.solar.isDate(cellDate, inSameDayAs: currentDate)

    if let monthDate, Calendar.solar.month(from: monthDate) == solarComponents.month {
      if Calendar.solar.isDateInWeekend(cellDate) && !isDateToday {
        solarLabel.alphaValue = AlphaLevels.secondary
      } else {
        solarLabel.alphaValue = AlphaLevels.primary
      }

      // Intentional, secondary alpha is used only for labels at weekends
      eventView.alphaValue = AlphaLevels.primary
    } else {
      solarLabel.alphaValue = AlphaLevels.tertiary
      eventView.alphaValue = AlphaLevels.tertiary
    }

    lunarLabel.alphaValue = solarLabel.alphaValue
    holidayView.alphaValue = eventView.alphaValue
  }

  @discardableResult
  func cancelHighlight() -> Bool {
    highlightView.alphaValue = 0
    return dismissDetails()
  }

  func setSelected(_ selected: Bool) {
    isDateSelected = selected
    // Update selection ring visibility
    let isDateToday = cellDate.map { Calendar.solar.isDate($0, inSameDayAs: Date.now) } ?? false
    selectionRingView.isHidden = !(isDateSelected && !isDateToday)
  }
}

// MARK: - Private

private extension DateGridCell {
  enum Constants {
    static let solarFontSize: Double = FontSizes.regular
    static let lunarFontSize: Double = FontSizes.small
    static let eventViewHeight: Double = 10
    static let focusRingBorderWidth: Double = 2
    static let selectionRingBorderWidth: Double = 2
    static let holidayViewImage: NSImage = .with(symbolName: Icons.bookmarkFill, pointSize: 9)
    static let lunarDateFormatter: DateFormatter = .lunarDate
  }

  func setUp() {
    view.addSubview(containerView)
    containerView.addAction { [weak self] in
      self?.handleCellClick()
    }

    highlightView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(highlightView)

    // 先添加 focusRingView（绿色圆形背景），确保在文字下方
    focusRingView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(focusRingView)

    // 添加 selectionRingView（绿色空心圆圈），用于非今天的选中状态
    selectionRingView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(selectionRingView)

    solarLabel.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(solarLabel)
    NSLayoutConstraint.activate([
      solarLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      solarLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: AppDesign.cellRectInset),
    ])

    lunarLabel.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(lunarLabel)
    NSLayoutConstraint.activate([
      lunarLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      lunarLabel.topAnchor.constraint(equalTo: solarLabel.bottomAnchor),
    ])

    eventView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(eventView)
    NSLayoutConstraint.activate([
      eventView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      eventView.topAnchor.constraint(equalTo: lunarLabel.bottomAnchor),
      eventView.heightAnchor.constraint(equalToConstant: Constants.eventViewHeight),
    ])

    NSLayoutConstraint.activate([
      highlightView.topAnchor.constraint(equalTo: containerView.topAnchor),
      highlightView.bottomAnchor.constraint(equalTo: eventView.bottomAnchor, constant: AppDesign.cellRectInset),
      highlightView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

      // Here we need to make sure the highlight view is wider than both labels
      highlightView.widthAnchor.constraint(
        greaterThanOrEqualTo: solarLabel.widthAnchor,
        constant: Constants.focusRingBorderWidth + AppDesign.cellRectInset * 2
      ),
      highlightView.widthAnchor.constraint(
        greaterThanOrEqualTo: lunarLabel.widthAnchor,
        constant: Constants.focusRingBorderWidth + AppDesign.cellRectInset * 2
      ),

      // focusRingView 设置为正方形，居中显示
      focusRingView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      focusRingView.centerYAnchor.constraint(equalTo: highlightView.centerYAnchor),
      focusRingView.widthAnchor.constraint(equalTo: focusRingView.heightAnchor),  // 宽高相等=正方形
      focusRingView.widthAnchor.constraint(equalTo: highlightView.widthAnchor),
      focusRingView.heightAnchor.constraint(lessThanOrEqualTo: highlightView.heightAnchor),

      // selectionRingView 与 focusRingView 相同大小和位置
      selectionRingView.centerXAnchor.constraint(equalTo: focusRingView.centerXAnchor),
      selectionRingView.centerYAnchor.constraint(equalTo: focusRingView.centerYAnchor),
      selectionRingView.widthAnchor.constraint(equalTo: focusRingView.widthAnchor),
      selectionRingView.heightAnchor.constraint(equalTo: focusRingView.heightAnchor),
    ])

    holidayView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(holidayView)
    NSLayoutConstraint.activate([
      holidayView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -3.5),
      holidayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -1.5),
      holidayView.widthAnchor.constraint(equalToConstant: holidayView.frame.width),
      holidayView.heightAnchor.constraint(equalToConstant: holidayView.frame.height),
    ])

    let longPressRecognizer = NSPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
    longPressRecognizer.minimumPressDuration = 0.5
    view.addGestureRecognizer(longPressRecognizer)
  }

  func handleCellClick() {
    guard let cellDate else {
      return Logger.assertFail("Missing cellDate to continue")
    }

    // Notify parent view to update event list
    onDateSelected?(cellDate, cellEvents)
  }

  func revealDateInCalendar() {
    guard let cellDate else {
      return Logger.assertFail("Missing cellDate to continue")
    }

    dismissDetails()
    (NSApp.delegate as? AppDelegate)?.openCalendar(targetDate: cellDate)
  }

  @objc func onLongPress(_ recognizer: NSPressGestureRecognizer) {
    guard recognizer.state == .began, let cellDate else {
      return
    }

    NSHapticFeedbackManager.defaultPerformer.perform(
      .generic,
      performanceTime: .now
    )

    dismissDetails()
    (NSApp.delegate as? AppDelegate)?.countDaysBetween(targetDate: cellDate)
  }

  @discardableResult
  func dismissDetails() -> Bool {
    let wasOpen = detailsPopover?.isShown == true
    detailsTask?.cancel()

    let closeDetails: @Sendable () -> Void = {
      Task { @MainActor in
        self.detailsPopover?.close()
        self.detailsPopover = nil
      }
    }

    if !AppPreferences.Accessibility.reduceMotion, let window = detailsPopover?.window {
      window.fadeOut(completion: closeDetails)
    } else {
      closeDetails()
    }

    return wasOpen
  }
}
