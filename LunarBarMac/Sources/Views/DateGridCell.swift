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

    view.layer?.borderWidth = 2.0  // 今日标记边框宽度
    view.layer?.cornerRadius = AppDesign.cellCornerRadius
    view.layer?.cornerCurve = .continuous
    // 边框颜色在 viewDidLayout 中设置

    return view
  }()

  private let selectionRingView: NSView = {
    let view = NSView()
    view.wantsLayer = true
    view.isHidden = true
    view.setAccessibilityHidden(true)

    view.layer?.borderWidth = 1.5  // 选中日期边框宽度
    // 边框颜色在 viewDidLayout 中设置
    view.layer?.cornerRadius = AppDesign.cellCornerRadius
    view.layer?.cornerCurve = .continuous
    view.layer?.backgroundColor = NSColor.clear.cgColor

    return view
  }()

  // Glass effect views for macOS 26+ (stored as Any to avoid availability issues)
  private var glassSelectionView: Any?
  private var glassFocusView: Any?

  private let holidayView: NSImageView = {
    let view = NSImageView()
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

    // 完全隐藏 highlightView，不再使用悬停效果
    highlightView.isHidden = true

    // 设置今日标记：只有轻微灰色背景，无边框
    let isDarkMode = view.effectiveAppearance.isDarkMode
    let todayBackgroundColor = isDarkMode ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)

    focusRingView.layer?.backgroundColor = todayBackgroundColor.cgColor
    focusRingView.layer?.borderWidth = 0  // 移除边框
    focusRingView.layer?.borderColor = nil

    // 使用固定尺寸的圆角半径，保证完美正圆
    let radius = Constants.fixedRingSize / 2
    focusRingView.layer?.cornerRadius = radius

    // 设置选中标记为细灰色边框
    let selectionBorderColor = isDarkMode ? NSColor.white.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.25)
    selectionRingView.layer?.borderColor = selectionBorderColor.cgColor
    selectionRingView.layer?.borderWidth = Constants.selectionRingBorderWidth  // 边框宽度
    selectionRingView.layer?.cornerRadius = radius  // 与 focusRingView 相同半径

    // Update Glass view corner radius and tint on macOS 26+
    if #available(macOS 26.0, *), AppDesign.modernStyle {
      // 今日 Glass（稍深）- 配合背景色
      (glassFocusView as? NSGlassEffectView)?.cornerRadius = radius
      let todayGlassTint = isDarkMode ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.08)
      (glassFocusView as? NSGlassEffectView)?.tintColor = todayGlassTint

      // 选中日期 Glass（适中）- 配合边框
      (glassSelectionView as? NSGlassEffectView)?.cornerRadius = radius  // 使用相同半径
      let selectionGlassTint = isDarkMode ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)
      (glassSelectionView as? NSGlassEffectView)?.tintColor = selectionGlassTint
    }
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

    // 同步今日 Glass 视图的显示状态 (macOS 26+)
    if #available(macOS 26.0, *), AppDesign.modernStyle {
      (glassFocusView as? NSGlassEffectView)?.isHidden = !isDateToday
    }

    // 今日脉冲动画已移除，保持静态效果

    // Show selection ring for selected non-today dates
    let shouldShowSelection = isDateSelected && !isDateToday
    selectionRingView.isHidden = !shouldShowSelection

    // 同步选中日期的 Glass 视图 (macOS 26+)
    if #available(macOS 26.0, *), AppDesign.modernStyle {
      (glassSelectionView as? NSGlassEffectView)?.isHidden = !shouldShowSelection
    }

    // 文字颜色保持统一，不因为是今天而改变
    solarLabel.textColor = Colors.primaryLabel
    lunarLabel.textColor = Colors.primaryLabel

    // Reload event dot views
    eventView.updateEvents(cellEvents)

    // Holiday indicator icons
    switch holidayType {
    case .none:
      holidayView.isHidden = true
      holidayView.image = nil
      holidayView.contentTintColor = nil
    case .workday:
      holidayView.isHidden = false
      holidayView.image = Constants.workdayIcon  // 补班日：公文包
      holidayView.contentTintColor = .systemRed
    case .holiday:
      holidayView.isHidden = false
      holidayView.image = Constants.holidayIcon  // 放假日：圆点
      holidayView.contentTintColor = .systemGreen
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
      // Current month: use primary color
      solarLabel.textColor = Colors.primaryLabel
      lunarLabel.textColor = Colors.primaryLabel

      if Calendar.solar.isDateInWeekend(cellDate) && !isDateToday {
        // Current month weekend: 70% alpha (medium strength)
        solarLabel.alphaValue = AlphaLevels.secondary
      } else {
        // Current month weekday: 100% alpha (strongest)
        solarLabel.alphaValue = AlphaLevels.primary
      }

      // Intentional, secondary alpha is used only for labels at weekends
      eventView.alphaValue = AlphaLevels.primary
    } else {
      // Non-current month: use secondary color with reduced alpha (weakest)
      solarLabel.textColor = Colors.secondaryLabel
      lunarLabel.textColor = Colors.secondaryLabel
      solarLabel.alphaValue = 0.6  // 60% alpha to ensure weaker than current month weekend

      // Event dots and holiday indicator use lower opacity
      eventView.alphaValue = 0.5
    }

    lunarLabel.alphaValue = solarLabel.alphaValue
    holidayView.alphaValue = eventView.alphaValue
  }

  @discardableResult
  func cancelHighlight() -> Bool {
    // highlightView 悬停效果已移除，保持为 0
    highlightView.alphaValue = 0
    return dismissDetails()
  }

  func setSelected(_ selected: Bool) {
    let wasSelected = isDateSelected
    isDateSelected = selected

    // Update selection ring visibility with animation
    let isDateToday = cellDate.map { Calendar.solar.isDate($0, inSameDayAs: Date.now) } ?? false
    let shouldShow = isDateSelected && !isDateToday

    // Only animate if the state actually changed
    if wasSelected != selected {
      animateSelection(show: shouldShow)
    } else if !shouldShow {
      selectionRingView.isHidden = true
    }
  }
}

// MARK: - Private

private extension DateGridCell {
  enum Constants {
    static let solarFontSize: Double = FontSizes.regular
    static let lunarFontSize: Double = FontSizes.small
    static let eventViewHeight: Double = 10
    static let focusRingBorderWidth: Double = 2
    static let selectionRingBorderWidth: Double = 1.5
    static let lunarDateFormatter: DateFormatter = .lunarDate
    // 节假日图标
    static let workdayIcon: NSImage = .with(symbolName: "briefcase.fill", pointSize: 9)  // 补班日：公文包
    static let holidayIcon: NSImage = .with(symbolName: "circle.fill", pointSize: 9)     // 放假日：圆点
    // 固定圆圈尺寸，保证所有日期大小一致且为正圆
    static let fixedRingSize: Double = 40  // 40pt 避免横向重合，偶数尺寸渲染更精确
  }

  enum AnimationConstants {
    // 只保留基本的淡入淡出时长
    static let selectionDuration: TimeInterval = 0.15
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
      // Ensure eventView has enough space from the bottom to prevent clipping
      eventView.bottomAnchor.constraint(
        lessThanOrEqualTo: containerView.bottomAnchor,
        constant: -AppDesign.cellRectInset
      ),
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

      // focusRingView 使用固定尺寸，保证所有日期大小一致且为正圆
      focusRingView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      focusRingView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
      focusRingView.widthAnchor.constraint(equalToConstant: Constants.fixedRingSize),
      focusRingView.heightAnchor.constraint(equalToConstant: Constants.fixedRingSize),

      // selectionRingView 与 focusRingView 相同大小和位置
      selectionRingView.centerXAnchor.constraint(equalTo: focusRingView.centerXAnchor),
      selectionRingView.centerYAnchor.constraint(equalTo: focusRingView.centerYAnchor),
      selectionRingView.widthAnchor.constraint(equalToConstant: Constants.fixedRingSize),
      selectionRingView.heightAnchor.constraint(equalToConstant: Constants.fixedRingSize),
    ])

    holidayView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(holidayView)
    NSLayoutConstraint.activate([
      holidayView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -3.5),
      holidayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -1.5),
      holidayView.widthAnchor.constraint(equalToConstant: 9),  // 固定宽度，与图标 pointSize 一致
      holidayView.heightAnchor.constraint(equalToConstant: 9),  // 固定高度
    ])

    let longPressRecognizer = NSPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
    longPressRecognizer.minimumPressDuration = 0.5
    view.addGestureRecognizer(longPressRecognizer)

    // Setup Glass effects for macOS 26+
    if #available(macOS 26.0, *), AppDesign.modernStyle {
      setupGlassEffects()
    }
  }

  @available(macOS 26.0, *)
  func setupGlassEffects() {
    let isDarkMode = view.effectiveAppearance.isDarkMode

    // 今日标记的 Glass effect（深色）
    let glassFocus = NSGlassEffectView()
    glassFocus.cornerRadius = AppDesign.cellCornerRadius
    let todayTint = isDarkMode ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.10)
    glassFocus.tintColor = todayTint
    glassFocus.translatesAutoresizingMaskIntoConstraints = false
    glassFocus.setAccessibilityHidden(true)

    containerView.addSubview(glassFocus, positioned: .below, relativeTo: focusRingView)
    NSLayoutConstraint.activate([
      glassFocus.centerXAnchor.constraint(equalTo: focusRingView.centerXAnchor),
      glassFocus.centerYAnchor.constraint(equalTo: focusRingView.centerYAnchor),
      glassFocus.widthAnchor.constraint(equalTo: focusRingView.widthAnchor),
      glassFocus.heightAnchor.constraint(equalTo: focusRingView.heightAnchor),
    ])
    self.glassFocusView = glassFocus

    // 选中日期的 Glass effect（浅色 + 边框）
    let glassSelection = NSGlassEffectView()
    glassSelection.cornerRadius = AppDesign.cellCornerRadius
    let selectionTint = isDarkMode ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04)
    glassSelection.tintColor = selectionTint
    glassSelection.translatesAutoresizingMaskIntoConstraints = false
    glassSelection.setAccessibilityHidden(true)

    containerView.addSubview(glassSelection, positioned: .below, relativeTo: selectionRingView)
    NSLayoutConstraint.activate([
      glassSelection.centerXAnchor.constraint(equalTo: selectionRingView.centerXAnchor),
      glassSelection.centerYAnchor.constraint(equalTo: selectionRingView.centerYAnchor),
      glassSelection.widthAnchor.constraint(equalTo: selectionRingView.widthAnchor),
      glassSelection.heightAnchor.constraint(equalTo: selectionRingView.heightAnchor),
    ])
    self.glassSelectionView = glassSelection
  }

  func handleCellClick() {
    guard let cellDate else {
      return Logger.assertFail("Missing cellDate to continue")
    }

    // Haptic feedback for glass-like tactile experience
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

    // Notify parent view to update event list immediately (no animation delay)
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

// MARK: - Animation Methods

private extension DateGridCell {
  /// 选中状态动画（自适应系统版本）
  func animateSelection(show: Bool) {
    let duration = AnimationConstants.selectionDuration

    if #available(macOS 26.0, *), AppDesign.modernStyle {
      animateGlassSelection(show: show, duration: duration)
    } else {
      animateTraditionalSelection(show: show, duration: duration)
    }
  }

  /// 传统系统的选中动画
  func animateTraditionalSelection(show: Bool, duration: TimeInterval) {
    guard !AppPreferences.Accessibility.reduceMotion else {
      selectionRingView.isHidden = !show
      return
    }

    // 只保留淡入/淡出动画，移除缩放和触感反馈
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      selectionRingView.animator().alphaValue = show ? 1.0 : 0.0
    }

    // 更新 isHidden 状态
    if !show {
      DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
        self?.selectionRingView.isHidden = true
      }
    } else {
      selectionRingView.isHidden = false
    }
  }

  /// macOS 26 的选中动画（玻璃背景 + 细边框）
  @available(macOS 26.0, *)
  func animateGlassSelection(show: Bool, duration: TimeInterval) {
    guard !AppPreferences.Accessibility.reduceMotion else {
      selectionRingView.isHidden = !show
      (glassSelectionView as? NSGlassEffectView)?.isHidden = !show
      return
    }

    // 同时动画边框和玻璃背景
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      selectionRingView.animator().alphaValue = show ? 1.0 : 0.0
      (glassSelectionView as? NSGlassEffectView)?.animator().alphaValue = show ? 1.0 : 0.0
    }

    // 更新 isHidden 状态
    if !show {
      DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
        self?.selectionRingView.isHidden = true
        (self?.glassSelectionView as? NSGlassEffectView)?.isHidden = true
      }
    } else {
      selectionRingView.isHidden = false
      (glassSelectionView as? NSGlassEffectView)?.isHidden = false
    }
  }
}
