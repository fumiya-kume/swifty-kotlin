import Foundation

/// Manages the on-disk cache for incremental compilation.
///
/// The primary cache files used by this type are:
/// ```
/// <cachePath>/
///   manifest.json       — file fingerprints from the previous build
///   deps.json           — dependency graph (symbol ↔ file relationships)
///   frontend.json       — reusable AST/interner state for file-level frontend work
///   artifacts/          — final output artifacts keyed by build configuration
/// ```
public final class IncrementalCompilationCache {
    public let cachePath: String

    private var previousFingerprints: [String: FileFingerprint] = [:]
    private var previousBuildConfigurationHash: String?
    private var previousOutputArtifact: CachedOutputArtifact?

    /// Dependency graph from the *previous* successful compilation.
    /// `nil` means no valid dependency graph was loaded (deps.json missing or corrupt).
    private var previousDependencyGraph: DependencyGraph?

    /// Fingerprints computed for the *current* compilation inputs.
    private var currentFingerprints: [String: FileFingerprint] = [:]

    public init(cachePath: String) {
        self.cachePath = cachePath
    }

    // MARK: - Loading previous state

    private static let supportedManifestVersion = 1

    /// Loads the manifest and dependency graph from the cache directory.
    /// If the cache doesn't exist, is corrupt, or has an unsupported version,
    /// starts fresh.
    public func loadPreviousState() {
        let fm = FileManager.default
        let manifestPath = cachePath + "/manifest.json"
        let depsPath = cachePath + "/deps.json"

        if fm.fileExists(atPath: manifestPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath))
        {
            let decoder = JSONDecoder()
            if let manifest = try? decoder.decode(CacheManifest.self, from: data),
               manifest.version == Self.supportedManifestVersion
            {
                for fp in manifest.fingerprints {
                    previousFingerprints[fp.path] = fp
                }
                previousBuildConfigurationHash = manifest.buildConfigurationHash
                previousOutputArtifact = manifest.outputArtifact
            }
        }

        if fm.fileExists(atPath: depsPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: depsPath))
        {
            if let graph = try? DependencyGraph.deserialize(from: data) {
                previousDependencyGraph = graph
            }
        }
    }

    // MARK: - Change detection

    public func computeCurrentFingerprints(for paths: [String], sourceManager: SourceManager) {
        currentFingerprints = [:]
        for path in paths {
            guard let fingerprint = computeCurrentFingerprint(for: path, sourceManager: sourceManager) else {
                continue
            }
            currentFingerprints[path] = fingerprint
        }
    }

    public func computeCurrentFingerprints(for paths: [String]) {
        currentFingerprints = [:]
        for path in paths {
            guard let fingerprint = computeCurrentFingerprint(for: path, sourceManager: nil) else {
                continue
            }
            currentFingerprints[path] = fingerprint
        }
    }

    public func changedFiles(allPaths: [String]) -> Set<String> {
        var changed = Set<String>()
        let allPathsSet = Set(allPaths)
        for path in allPaths {
            guard let current = currentFingerprints[path] else {
                // File could not be fingerprinted — treat as changed.
                changed.insert(path)
                continue
            }
            guard let previous = previousFingerprints[path] else {
                // New file — treat as changed.
                changed.insert(path)
                continue
            }
            if current.contentChanged(from: previous) {
                changed.insert(path)
            }
        }
        // Files that were in the previous build but removed in this build
        // must be treated as changed so their provided symbols are invalidated
        // and dependents are recompiled.
        for previousPath in previousFingerprints.keys where !allPathsSet.contains(previousPath) {
            changed.insert(previousPath)
        }
        return changed
    }

    /// Computes the full recompilation set using the dependency graph.
    /// Returns `nil` if no cache is available (full build needed), including
    /// when the dependency graph is missing or corrupt.
    public func recompilationSet(allPaths: [String], options: CompilerOptions? = nil) -> Set<String>? {
        if previousFingerprints.isEmpty {
            // No previous build — full build needed.
            return nil
        }

        if let options,
           previousBuildConfigurationHash != Self.buildConfigurationHash(for: options)
        {
            return nil
        }

        guard let depGraph = previousDependencyGraph else {
            // Dependency graph missing or corrupt — full build needed.
            return nil
        }

        let changed = changedFiles(allPaths: allPaths)
        if changed.isEmpty {
            return Set()
        }

        let recompFiles = depGraph.recompilationSet(
            changedFiles: changed,
            allFiles: allPaths
        )
        return Set(recompFiles)
    }

    public func restoreCachedOutput(for options: CompilerOptions) -> Bool {
        guard previousBuildConfigurationHash == Self.buildConfigurationHash(for: options),
              let artifact = previousOutputArtifact
        else {
            return false
        }

        let sourcePath = cachePath + "/" + artifact.relativePath
        var sourceIsDirectory = ObjCBool(false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath, isDirectory: &sourceIsDirectory) else {
            return false
        }
        if artifact.kind == .directory, !sourceIsDirectory.boolValue {
            return false
        }
        if artifact.kind == .file, sourceIsDirectory.boolValue {
            return false
        }

        let destinationPath = Self.outputArtifactPath(for: options)
        if URL(fileURLWithPath: sourcePath).standardizedFileURL.path
            == URL(fileURLWithPath: destinationPath).standardizedFileURL.path
        {
            return true
        }

        do {
            try Self.removeItemIfPresent(at: destinationPath, fileManager: fm)
            let parent = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try fm.copyItem(atPath: sourcePath, toPath: destinationPath)
            return true
        } catch {
            return false
        }
    }

    public var hasPreviousCache: Bool {
        !previousFingerprints.isEmpty
    }

    public var dependencyGraph: DependencyGraph? {
        previousDependencyGraph
    }

    public func buildConfigurationHash(for options: CompilerOptions) -> String {
        Self.buildConfigurationHash(for: options)
    }

    public func loadFrontendState(for options: CompilerOptions) -> IncrementalFrontendState? {
        let buildHash = Self.buildConfigurationHash(for: options)
        guard previousBuildConfigurationHash == buildHash else {
            return nil
        }
        let frontendPath = cachePath + "/frontend.json"
        guard FileManager.default.fileExists(atPath: frontendPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: frontendPath))
        else {
            return nil
        }
        guard let state = try? JSONDecoder().decode(IncrementalFrontendState.self, from: data),
              state.version == IncrementalFrontendState.supportedVersion,
              state.buildConfigurationHash == buildHash
        else {
            return nil
        }
        return state
    }

    // MARK: - Saving state

    /// Saves the current fingerprints and the updated dependency graph to disk.
    public func saveState(
        dependencyGraph: DependencyGraph,
        options: CompilerOptions? = nil,
        frontendState: IncrementalFrontendState? = nil
    ) {
        let fm = FileManager.default

        do {
            if !fm.fileExists(atPath: cachePath) {
                try fm.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
            }

            let fingerprints = currentFingerprints.values.sorted(by: { $0.path < $1.path })
            let manifest = CacheManifest(
                version: 1,
                fingerprints: Array(fingerprints),
                buildConfigurationHash: options.map(Self.buildConfigurationHash(for:)),
                outputArtifact: options.flatMap { cacheOutputArtifact(for: $0, fileManager: fm) }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: URL(fileURLWithPath: cachePath + "/manifest.json"),
                options: .atomic
            )

            let depsData = try dependencyGraph.serialize()
            try depsData.write(
                to: URL(fileURLWithPath: cachePath + "/deps.json"),
                options: .atomic
            )

            if let frontendState {
                let frontendEncoder = JSONEncoder()
                frontendEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                let frontendData = try frontendEncoder.encode(frontendState)
                try frontendData.write(
                    to: URL(fileURLWithPath: cachePath + "/frontend.json"),
                    options: .atomic
                )
            } else {
                try? fm.removeItem(atPath: cachePath + "/frontend.json")
            }

            previousFingerprints = currentFingerprints
            previousBuildConfigurationHash = manifest.buildConfigurationHash
            previousOutputArtifact = manifest.outputArtifact
            previousDependencyGraph = dependencyGraph
        } catch {
            // Cache save failure is non-fatal — next build will do a full compile.
            let message = "[IncrementalCompilationCache] Failed to save cache at '\(cachePath)': \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }

    public func clearCache() {
        try? FileManager.default.removeItem(atPath: cachePath)
        previousFingerprints = [:]
        previousBuildConfigurationHash = nil
        previousOutputArtifact = nil
        previousDependencyGraph = nil
        currentFingerprints = [:]
    }

    private func computeCurrentFingerprint(for path: String, sourceManager: SourceManager?) -> FileFingerprint? {
        if let sourceManager, let fileID = sourceManager.fileID(forPath: path) {
            let contents = sourceManager.contents(of: fileID)
            return FileFingerprint.compute(for: path, contents: contents)
        }
        return FileFingerprint.compute(for: path)
    }

    private func cacheOutputArtifact(
        for options: CompilerOptions,
        fileManager fm: FileManager
    ) -> CachedOutputArtifact? {
        let sourcePath = Self.outputArtifactPath(for: options)
        var isDirectory = ObjCBool(false)
        guard fm.fileExists(atPath: sourcePath, isDirectory: &isDirectory) else {
            return nil
        }

        let relativePath = "artifacts/\(Self.buildConfigurationHash(for: options))/output"
        let destinationPath = cachePath + "/" + relativePath
        do {
            try Self.removeItemIfPresent(at: destinationPath, fileManager: fm)
            let parent = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try fm.copyItem(atPath: sourcePath, toPath: destinationPath)
            return CachedOutputArtifact(
                kind: isDirectory.boolValue ? .directory : .file,
                relativePath: relativePath
            )
        } catch {
            return nil
        }
    }

    private static func removeItemIfPresent(at path: String, fileManager fm: FileManager) throws {
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }

    private static func outputArtifactPath(for options: CompilerOptions) -> String {
        switch options.emit {
        case .kirDump:
            outputPath(base: options.outputPath, defaultExtension: "kir")
        case .llvmIR:
            outputPath(base: options.outputPath, defaultExtension: "ll")
        case .object:
            outputPath(base: options.outputPath, defaultExtension: "o")
        case .executable:
            options.outputPath
        case .library:
            options.outputPath.hasSuffix(".kklib") ? options.outputPath : options.outputPath + ".kklib"
        }
    }

    private static func outputPath(base: String, defaultExtension: String) -> String {
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension.isEmpty {
            return fileURL.appendingPathExtension(defaultExtension).path
        }
        return base
    }

    private static func buildConfigurationHash(for options: CompilerOptions) -> String {
        let config = IncrementalBuildConfiguration(
            schemaVersion: 1,
            moduleName: options.moduleName,
            inputPaths: options.inputs,
            emit: options.emit.rawValue,
            searchPaths: options.searchPaths,
            libraryPaths: options.libraryPaths,
            linkLibraries: options.linkLibraries,
            target: IncrementalTargetTriple(
                arch: options.target.arch,
                vendor: options.target.vendor,
                os: options.target.os,
                osVersion: options.target.osVersion
            ),
            optLevel: options.optLevel.rawValue,
            debugInfo: options.debugInfo,
            frontendFlags: options.frontendFlags.filter(Self.isOutputAffectingFrontendFlag),
            irFlags: options.irFlags,
            runtimeFlags: options.runtimeFlags
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(config)) ?? Data()
        return stableFNV1a64Hex(String(decoding: data, as: UTF8.self))
    }

    private static func isOutputAffectingFrontendFlag(_ flag: String) -> Bool {
        flag != "incremental" && flag != "time-phases" && !flag.hasPrefix("jobs=")
    }

    private static func stableFNV1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Cache manifest model

struct CacheManifest: Codable {
    let version: Int
    let fingerprints: [FileFingerprint]
    let buildConfigurationHash: String?
    let outputArtifact: CachedOutputArtifact?

    init(
        version: Int,
        fingerprints: [FileFingerprint],
        buildConfigurationHash: String? = nil,
        outputArtifact: CachedOutputArtifact? = nil
    ) {
        self.version = version
        self.fingerprints = fingerprints
        self.buildConfigurationHash = buildConfigurationHash
        self.outputArtifact = outputArtifact
    }
}

struct CachedOutputArtifact: Codable, Equatable {
    let kind: CachedOutputArtifactKind
    let relativePath: String
}

enum CachedOutputArtifactKind: String, Codable {
    case file
    case directory
}

private struct IncrementalBuildConfiguration: Encodable {
    let schemaVersion: Int
    let moduleName: String
    let inputPaths: [String]
    let emit: String
    let searchPaths: [String]
    let libraryPaths: [String]
    let linkLibraries: [String]
    let target: IncrementalTargetTriple
    let optLevel: Int
    let debugInfo: Bool
    let frontendFlags: [String]
    let irFlags: [String]
    let runtimeFlags: [String]
}

private struct IncrementalTargetTriple: Encodable {
    let arch: String
    let vendor: String
    let os: String
    let osVersion: String?
}
