// ScriptWatcher.swift
// OCCTSwiftMetalDemo
//
// Watches for script harness output (manifest.json + BREP files) and auto-loads geometry.
// macOS: watches iCloud Drive + local fallback via kqueue
// iOS: watches iCloud Drive via polling timer (iCloud syncs files from Mac)
//
// Output directory: ~/Library/Mobile Documents/com~apple~CloudDocs/OCCTSwiftScripts/output/
// Fallback (macOS only): ~/.occtswift-scripts/output/

import Foundation
import Combine
import OCCTSwift
import OCCTSwiftViewport
import OCCTSwiftTools

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
    @Published var availableScripts: [ScriptEntry] = []
    @Published var manifestMetadata: ScriptManifest.ManifestMetadata?

    /// A discovered script output directory with its manifest.
    struct ScriptEntry: Identifiable {
        let id: String  // directory name
        let url: URL
        let manifest: ScriptManifest
        var name: String { manifest.metadata?.name ?? manifest.description ?? id }
        var bodyCount: Int { manifest.bodies.count }
        var timestamp: Date { manifest.timestamp }
    }

    private let iCloudDir: URL?
    private let localDir: URL

    #if os(macOS)
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    #endif
    private var pollTimer: Foundation.Timer?
    private var debounceTimer: Foundation.Timer?
    private var lastManifestDate: Date?

    init() {
        let fm = FileManager.default

        #if os(macOS)
        let home = fm.homeDirectoryForCurrentUser
        localDir = home.appendingPathComponent(".occtswift-scripts/output")
        let mobileDocsDir = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let icloudPath = mobileDocsDir.appendingPathComponent("OCCTSwiftScripts/output")
        if fm.fileExists(atPath: mobileDocsDir.path) {
            iCloudDir = icloudPath
        } else {
            iCloudDir = nil
        }
        #else
        // On iOS, use the iCloud ubiquity container or Documents as fallback
        localDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OCCTSwiftScripts/output")

        // iCloud Drive via ubiquity container URL
        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            iCloudDir = ubiquityURL.appendingPathComponent("Documents/OCCTSwiftScripts/output")
        } else {
            // Fallback: try the mobile documents path directly
            // On iOS this is accessible if iCloud Drive is enabled
            let mobileDocs = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            let icloudPath = mobileDocs.appendingPathComponent("OCCTSwiftScripts/output")
            if fm.fileExists(atPath: mobileDocs.path) {
                iCloudDir = icloudPath
            } else {
                iCloudDir = nil
            }
        }
        #endif
    }

    /// The active output directory (iCloud preferred, local fallback).
    var outputDir: URL {
        if let iCloudDir, FileManager.default.fileExists(atPath: iCloudDir.deletingLastPathComponent().path) {
            return iCloudDir
        }
        return localDir
    }

    /// The scripts root directory (parent of output/).
    private var scriptsRootDir: URL {
        outputDir.deletingLastPathComponent()
    }

    func reload() {
        scanForScripts()
        loadManifest()
    }

    /// Load a specific script entry from the gallery.
    func loadScript(_ entry: ScriptEntry) {
        let manifestURL = entry.url.appendingPathComponent("manifest.json")
        loadManifestAt(manifestURL)
    }

    // MARK: - File Watching

    private func startWatching() {
        stopWatching()

        // Ensure output directory exists
        let fm = FileManager.default
        try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        #if os(macOS)
        startKqueueWatcher()
        #endif

        // iOS and macOS both use polling for iCloud (iCloud changes don't trigger kqueue)
        startPolling()

        lastError = nil
        scanForScripts()

        // Check for existing manifest
        let manifestURL = outputDir.appendingPathComponent("manifest.json")
        ensureDownloaded(manifestURL)
        if fm.fileExists(atPath: manifestURL.path) {
            loadManifest()
        }
    }

    private func stopWatching() {
        #if os(macOS)
        stopKqueueWatcher()
        #endif
        pollTimer?.invalidate()
        pollTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    #if os(macOS)
    private func startKqueueWatcher() {
        dirFD = open(outputDir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }

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
    }

    private func stopKqueueWatcher() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }
    #endif

    private func startPolling() {
        // Poll every 2 seconds for iCloud changes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    private func handleDirectoryChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.scanForScripts()
                self?.loadManifest()
            }
        }
    }

    private func checkForChanges() {
        let manifestURL = outputDir.appendingPathComponent("manifest.json")
        ensureDownloaded(manifestURL)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }

        // Check if manifest modification date changed
        if let attrs = try? FileManager.default.attributesOfItem(atPath: manifestURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            if modDate != lastManifestDate {
                lastManifestDate = modDate
                scanForScripts()
                loadManifest()
            }
        }
    }

    // MARK: - iCloud Download

    private func ensureDownloaded(_ url: URL) {
        // If the file is in iCloud but not downloaded, trigger download
        guard iCloudDir != nil else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }
    }

    // MARK: - Script Discovery

    private func scanForScripts() {
        let fm = FileManager.default
        var entries: [ScriptEntry] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Check the main output directory
        let mainManifest = outputDir.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: mainManifest),
           let manifest = try? decoder.decode(ScriptManifest.self, from: data) {
            entries.append(ScriptEntry(
                id: "current",
                url: outputDir,
                manifest: manifest
            ))
        }

        // Scan for named subdirectories (future: multiple script outputs)
        let scriptsRoot = scriptsRootDir
        if let contents = try? fm.contentsOfDirectory(at: scriptsRoot,
                                                       includingPropertiesForKeys: [.isDirectoryKey]) {
            for dirURL in contents {
                guard dirURL.lastPathComponent != "output" else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

                let manifest = dirURL.appendingPathComponent("manifest.json")
                ensureDownloaded(manifest)
                if let data = try? Data(contentsOf: manifest),
                   let m = try? decoder.decode(ScriptManifest.self, from: data) {
                    entries.append(ScriptEntry(id: dirURL.lastPathComponent, url: dirURL, manifest: m))
                }
            }
        }

        entries.sort { $0.timestamp > $1.timestamp }
        availableScripts = entries
    }

    // MARK: - Manifest Loading

    private func loadManifest() {
        let manifestURL = outputDir.appendingPathComponent("manifest.json")
        loadManifestAt(manifestURL)
    }

    private func loadManifestAt(_ manifestURL: URL) {
        ensureDownloaded(manifestURL)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            lastError = "No manifest.json found"
            return
        }

        // Ensure BREP files are downloaded
        let baseDir = manifestURL.deletingLastPathComponent()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(ScriptManifest.self, from: data) else {
            lastError = "Failed to parse manifest"
            return
        }

        // Trigger downloads for all BREP files
        for body in manifest.bodies {
            let brepURL = baseDir.appendingPathComponent(body.file)
            ensureDownloaded(brepURL)
        }

        do {
            let result = try CADFileLoader.loadFromManifest(at: manifestURL)
            scriptBodies = result.bodies
            scriptShapes = result.shapes
            manifestMetadata = manifest.metadata
            lastLoadTime = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
