// ScriptWatcher.swift
// OCCTSwiftMetalDemo
//
// Watches ~/.occtswift-scripts/output/ for manifest.json changes
// and auto-loads BREP geometry from the script harness.

#if os(macOS)
import Foundation
import Combine
import OCCTSwift
import OCCTSwiftViewport

@MainActor
final class ScriptWatcher: ObservableObject {
    @Published var isWatching = false {
        didSet {
            if isWatching { startWatching() } else { stopWatching() }
        }
    }
    @Published var lastLoadTime: Date?
    @Published var lastError: String?
    @Published var scriptBodies: [ViewportBody] = []
    @Published var scriptShapes: [Shape] = []

    private let outputDir: URL
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var debounceTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        outputDir = home.appendingPathComponent(".occtswift-scripts/output")
    }

    deinit {
        stopWatchingSync()
    }

    func reload() {
        loadManifest()
    }

    // MARK: - File Watching

    private func startWatching() {
        stopWatchingSync()

        // Ensure output directory exists
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        dirFD = open(outputDir.path, O_EVTONLY)
        guard dirFD >= 0 else {
            lastError = "Cannot open watch directory"
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.dirFD >= 0 {
                close(self.dirFD)
                self.dirFD = -1
            }
        }

        source.resume()
        dispatchSource = source
        lastError = nil

        // Check for existing manifest on start
        let manifestURL = outputDir.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            loadManifest()
        }
    }

    private func stopWatching() {
        stopWatchingSync()
    }

    private nonisolated func stopWatchingSync() {
        MainActor.assumeIsolated {
            debounceTimer?.invalidate()
            debounceTimer = nil
            dispatchSource?.cancel()
            dispatchSource = nil
        }
    }

    private func handleDirectoryChange() {
        // Debounce: wait 200ms for writes to settle
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.loadManifest()
            }
        }
    }

    // MARK: - Manifest Loading

    private func loadManifest() {
        let manifestURL = outputDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            lastError = "No manifest.json found"
            return
        }

        do {
            let result = try CADFileLoader.loadFromManifest(at: manifestURL)
            scriptBodies = result.bodies
            scriptShapes = result.shapes
            lastLoadTime = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
#endif
