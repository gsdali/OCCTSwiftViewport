// MetalSpikeApp.swift
// Metal renderer demo for OCCTSwiftViewport.

import SwiftUI
import CoreFoundation

/// Entry point. Branches on `--test-all-demos`: headless mode runs the demo
/// suite without booting AppKit/SwiftUI (so launchd / cron / SSH can drive it
/// reliably); interactive mode launches the SwiftUI app as normal.
@main
enum AppEntry {
    static func main() {
        if ProcessInfo.processInfo.arguments.contains("--test-all-demos") {
            runHeadless()
        } else {
            OCCTSwiftMetalDemoApp.main()
        }
    }

    /// Runs DemoTestRunner without booting NSApplication.
    /// Required for unattended overnight / CI runs because launchd-spawned
    /// SwiftUI apps don't get WindowServer activation, so `.onAppear` and
    /// even GCD scheduling on AppKit's main loop never fire.
    private static func runHeadless() {
        Task { @MainActor in
            DemoTestRunner.runAll(
                loadDemo: { _, _ in },     // no UI updates in headless mode
                completion: { passed, failed in
                    print("Test complete: \(passed) passed, \(failed) failed")
                    fflush(stdout)
                    exit(failed > 0 ? 1 : 0)
                }
            )
        }
        // DemoTestRunner uses DispatchQueue.main.asyncAfter to batch demos —
        // pump the main run loop so dispatched work actually runs.
        CFRunLoopRun()
    }
}

struct OCCTSwiftMetalDemoApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeView()
        }
    }
}
