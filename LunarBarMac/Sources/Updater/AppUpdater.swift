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
  private static let sparkleController: SPUStandardUpdaterController? = {
    // Initialize Sparkle's standard updater controller
    SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  }()
  #endif

  static func checkForUpdates(explicitly: Bool) async {
    #if canImport(Sparkle)
    if let controller = sparkleController {
      DispatchQueue.main.async {
        controller.checkForUpdates(nil)
      }
      return
    }
    #endif
    if explicitly {
      DispatchQueue.main.async { presentUnavailable() }
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

// MARK: - Private

private extension Localized {
  enum Updater {
    static let updateFailedTitle = String(localized: "Failed to get the update.", comment: "Title for failed to get the update")
    static let updateFailedMessage = String(localized: "Please configure the updater.", comment: "Message for failed to get the update")
  }
}

private extension AppPreferences {
  enum Updater {
    @Storage(key: "updater.skipped-versions", defaultValue: Set())
    static var skippedVersions: Set<String>
  }
}
