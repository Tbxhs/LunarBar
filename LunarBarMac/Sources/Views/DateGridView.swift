//
//  DateGridView.swift
//  LunarBarMac
//
//  Created by cyan on 12/21/23.
//

import AppKit
import EventKit
import LunarBarKit

/**
 Grid view to show dates of a month.
 */
final class DateGridView: NSView {
  private var monthDate: Date?
  private var lunarInfo: LunarInfo?
  private var dataSource: NSCollectionViewDiffableDataSource<Section, Model>?
  private var selectedDate: Date?

  // Callback when a date is selected
  var onDateSelected: ((Date, [EKCalendarItem]) -> Void)?

  private let collectionView: NSCollectionView = {
    let view = NSCollectionView()
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.group)
    view.setAccessibilityLabel(Localized.UI.accessibilityDateGridArea)
    view.setAccessibilityHelp(Localized.UI.accessibilityEnterToSelectDates)
    view.backgroundColors = [.clear]

    return view
  }()

  init() {
    super.init(frame: .zero)

    dataSource = NSCollectionViewDiffableDataSource<Section, Model>(collectionView: collectionView) { [weak self] (collectionView: NSCollectionView, indexPath: IndexPath, object: Model) -> NSCollectionViewItem? in
      let cell = collectionView.makeItem(withIdentifier: DateGridCell.reuseIdentifier, for: indexPath)
      if let cell = cell as? DateGridCell {
        cell.updateViews(
          cellDate: object.date,
          cellEvents: object.events,
          monthDate: self?.monthDate,
          lunarInfo: self?.lunarInfo
        )

        // Set selection callback
        cell.onDateSelected = { [weak self] date, events in
          self?.handleDateSelection(date: date, events: events)
        }

        // Update selection state
        if let self, let selectedDate = self.selectedDate {
          let isSelected = Calendar.solar.isDate(object.date, inSameDayAs: selectedDate)
          cell.setSelected(isSelected)
        } else {
          cell.setSelected(false)
        }
      } else {
        Logger.assertFail("Invalid cell type is found: \(cell)")
      }

      return cell
    }

    collectionView.collectionViewLayout = createLayout()
    collectionView.register(DateGridCell.self, forItemWithIdentifier: DateGridCell.reuseIdentifier)
    collectionView.delegate = self
    addSubview(collectionView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    collectionView.frame = bounds
  }

  @discardableResult
  func cancelHighlight() -> Bool {
    var cancelled = false
    visibleCells.forEach {
      cancelled = cancelled || $0.cancelHighlight()
    }

    return cancelled
  }

  func selectDate(_ date: Date?) {
    selectedDate = date
    // Update all visible cells
    visibleCells.forEach { cell in
      if let cellDate = cell.cellDate, let selectedDate {
        cell.setSelected(Calendar.solar.isDate(cellDate, inSameDayAs: selectedDate))
      } else {
        cell.setSelected(false)
      }
    }
  }

  func clearSelection() {
    selectedDate = nil
    visibleCells.forEach { $0.setSelected(false) }
  }

  private func handleDateSelection(date: Date, events: [EKCalendarItem]) {
    // Don't do anything if the same date is clicked again
    if let selectedDate, Calendar.solar.isDate(date, inSameDayAs: selectedDate) {
      return
    }

    // Update selection
    selectedDate = date

    // Update all cells
    visibleCells.forEach { cell in
      if let cellDate = cell.cellDate {
        cell.setSelected(Calendar.solar.isDate(cellDate, inSameDayAs: date))
      } else {
        cell.setSelected(false)
      }
    }

    // Notify parent view
    onDateSelected?(date, events)
  }
}

// MARK: - NSCollectionViewDelegate

extension DateGridView: NSCollectionViewDelegate {
  func collectionView(
    _ collectionView: NSCollectionView,
    shouldSelectItemsAt indexPaths: Set<IndexPath>
  ) -> Set<IndexPath> {
    // This is to disable the selection, which can be triggered by VoiceOver
    Set()
  }
}

// MARK: - Updating

extension DateGridView {
  func updateCalendar(date monthDate: Date, lunarInfo: LunarInfo?) {
    guard let allDates = Calendar.solar.allDatesFillingMonth(from: monthDate) else {
      return Logger.assertFail("Failed to generate the calendar")
    }

    guard let startDate = allDates.first, let endDate = allDates.last else {
      return Logger.assertFail("Missing any dates from: \(monthDate)")
    }

    self.monthDate = monthDate
    self.lunarInfo = lunarInfo
    self.reloadData(
      allDates: allDates,
      events: CalendarManager.default.caches(from: startDate, to: endDate)
    )

    Task {
      let items = try await CalendarManager.default.items(from: startDate, to: endDate)
      reloadData(allDates: allDates, events: items, diffable: false)

      // Months that can be easily navigated
      let preloadDates = [
        Calendar.solar.date(byAdding: .day, value: -1, to: startDate),
        Calendar.solar.date(byAdding: .day, value: 1, to: endDate),
        Calendar.solar.date(byAdding: .year, value: -1, to: monthDate),
        Calendar.solar.date(byAdding: .year, value: 1, to: monthDate),
      ].compactMap { $0 }

      for preloadDate in preloadDates {
        await CalendarManager.default.preload(date: preloadDate)
      }
    }
  }
}

// MARK: - Private

private extension DateGridView {
  enum Section {
    case `default`
  }

  var visibleCells: [DateGridCell] {
    collectionView.visibleItems().compactMap {
      $0 as? DateGridCell
    }
  }

  /**
   Returns a 7 (column) * 6 (rows) grid layout for the collection.
   */
  func createLayout() -> NSCollectionViewLayout {
    let spacing = CGFloat(AppDesign.dateCellSpacing)
    let item = NSCollectionLayoutItem(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1 / Double(Calendar.solar.numberOfDaysInWeek)),
        heightDimension: .fractionalHeight(1)
      )
    )
    item.contentInsets = NSDirectionalEdgeInsets(
      top: spacing * 0.5,
      leading: spacing * 0.5 + 1,
      bottom: spacing * 0.5,
      trailing: spacing * 0.5 + 1
    )

    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1),
        heightDimension: .fractionalHeight(1 / Double(Calendar.solar.numberOfRowsInMonth))
      ),
      subitems: [item]
    )

    let section = NSCollectionLayoutSection(group: group)
    section.interGroupSpacing = 0
    section.contentInsets = NSDirectionalEdgeInsets(
      top: 0,
      leading: 0,
      bottom: 1,  // Adjusted to match left/right margins (2.5pt total with item bottom inset)
      trailing: 0
    )
    let layout = NSCollectionViewCompositionalLayout(section: section)
    return layout
  }

  @MainActor
  func reloadData(allDates: [Date], events: [EKCalendarItem]?, diffable: Bool = true) {
    cancelHighlight()
    Logger.log(.info, "Reloading dateGridView: \(allDates.count) items")

    var snapshot = NSDiffableDataSourceSnapshot<Section, Model>()
    snapshot.appendSections([Section.default])

    snapshot.appendItems(allDates.map { date in
      Model(date: date, events: events?.filter {
        $0.overlaps(
          startOfDay: Calendar.solar.startOfDay(for: date),
          endOfDay: Calendar.solar.endOfDay(for: date)
        )
      }.oldestToNewest ?? [])
    })

    // Disable the animation when cache is not hit, to avoid subsequent updates being ignored
    let animated = diffable && events != nil && !AppPreferences.Accessibility.reduceMotion
    dataSource?.apply(snapshot, animatingDifferences: animated)

    // Force update of certain properties that are not part of the diffable model
    visibleCells.forEach {
      $0.updateOpacity(monthDate: monthDate)
    }
  }
}

private struct Model: Hashable {
  let date: Date
  let events: [EKCalendarItem]

  func hash(into hasher: inout Hasher) {
    hasher.combine(date)
    hasher.combine(events)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.date == rhs.date && lhs.events == rhs.events
  }
}
