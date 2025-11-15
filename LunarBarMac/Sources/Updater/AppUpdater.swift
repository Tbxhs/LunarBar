//
//  AppUpdater.swift
//  LunarBarMac
//
//  Created by cyan on 12/25/23.
//

import AppKit
import LunarBarKit
#if canImport(Sparkle)
import Sparkle
#endif

enum AppUpdater {
#if canImport(Sparkle)
  private static var sparkleController: SPUStandardUpdaterController?

  static func configureSparkleController(_ controller: SPUStandardUpdaterController) {
    sparkleController = controller
  }
#endif

  static func checkForUpdates(explicitly: Bool) async {
#if canImport(Sparkle)
    if let controller = sparkleController {
      await MainActor.run {
        if explicitly {
          NSApp.activate(ignoringOtherApps: true)
          controller.checkForUpdates(nil)
        } else {
          controller.updater.checkForUpdatesInBackground()
        }
      }
      return
    }
#endif

    if explicitly {
      await MainActor.run {
        presentUnavailable()
      }
    }
  }
}

// MARK: - Private

@MainActor
private extension AppUpdater {
  static func presentUnavailable() {
    let alert = NSAlert()
    alert.messageText = Localized.Updater.updateFailedTitle
    alert.informativeText = String(localized: "Sparkle updater is not configured. Please set SUFeedURL and SUPublicEDKey.")
    alert.addButton(withTitle: Localized.General.learnMore)
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.safelyOpenURL(string: "https://sparkle-project.org/documentation/")
    }
  }
}

private extension Localized {
  enum Updater {
    static let updateFailedTitle = String(localized: "Failed to get the update.", comment: "Title for failed to get the update")
  }
}
