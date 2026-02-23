import Foundation

/// Manages the on-disk cache for incremental compilation.
///
/// The primary cache files used by this type are:
/// ```
/// <cachePath>/
///   manifest.json       — file fingerprints from the previous build
///   deps.json           — dependency graph (symbol ↔ file relationships)
///   per-file/           — (reserved for per-file artifacts; not used here yet)
///     <hash>.kirbin     — serialized per-file frontend results (written/read by other components)
/// ```
public final class IncrementalCompilationCache {

    /// Root directory of the cache.
    public let cachePath: String

    /// Fingerprints from the *previous* successful compilation.
    private var previousFingerprints: [String: FileFingerprint] = [:]

    /// Dependency graph from the *previous* successful compilation.
    /// `nil` means no valid dependency graph was loaded (deps.json missing or corrupt).
    private var previousDependencyGraph: DependencyGraph?

    /// Fingerprints computed for the *current* compilation inputs.
    private var currentFingerprints: [String: FileFingerprint] = [:]

    public init(cachePath: String) {
        self.cachePath = cachePath
    }

    // MARK: - Loading previous state

    /// Current supported manifest version. Older/newer versions are ignored.
    private static let supportedManifestVersion = 1

    /// Loads the manifest and dependency graph from the cache directory.
    /// If the cache doesn't exist, is corrupt, or has an unsupported version,
    /// starts fresh.
    public func loadPreviousState() {
        let fm = FileManager.default
        let manifestPath = cachePath + "/manifest.json"
        let depsPath = cachePath + "/deps.json"

        if fm.fileExists(atPath: manifestPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) {
            let decoder = JSONDecoder()
            if let manifest = try? decoder.decode(CacheManifest.self, from: data),
               manifest.version == Self.supportedManifestVersion {
                for fp in manifest.fingerprints {
                    previousFingerprints[fp.path] = fp
                }
            }
        }

        if fm.fileExists(atPath: depsPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: depsPath)) {
            if let graph = try? DependencyGraph.deserialize(from: data) {
                previousDependencyGraph = graph
            }
        }
    }

    // MARK: - Change detection

    /// Computes fingerprints for the given input paths and stores them as current.
    public func computeCurrentFingerprints(for paths: [String], sourceManager: SourceManager) {
        for path in paths {
            // Try to get contents from sourceManager first (already loaded)
            let fileIDs = sourceManager.fileIDs()
            var found = false
            for fileID in fileIDs {
                if sourceManager.path(of: fileID) == path {
                    let contents = sourceManager.contents(of: fileID)
                    let fp = FileFingerprint.compute(for: path, contents: contents)
                    currentFingerprints[path] = fp
                    found = true
                    break
                }
            }
            if !found {
                if let fp = FileFingerprint.compute(for: path) {
                    currentFingerprints[path] = fp
                }
            }
        }
    }

    /// Computes fingerprints directly from path list (without SourceManager).
    public func computeCurrentFingerprints(for paths: [String]) {
        for path in paths {
            if let fp = FileFingerprint.compute(for: path) {
                currentFingerprints[path] = fp
            }
        }
    }

    /// Returns the set of files whose content hash has changed since the last build.
    /// Files that are new (not in previous manifest) are also considered changed.
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
            // Fast path: if mtime is the same, skip hash comparison.
            if current.mtimeUnchanged(from: previous) {
                continue
            }
            // Slow path: compare content hashes.
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
    public func recompilationSet(allPaths: [String]) -> Set<String>? {
        if previousFingerprints.isEmpty {
            // No previous build — full build needed.
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

    /// Returns `true` if a previous cache exists.
    public var hasPreviousCache: Bool {
        !previousFingerprints.isEmpty
    }

    /// Returns the previous dependency graph (for querying after load).
    public var dependencyGraph: DependencyGraph? {
        previousDependencyGraph
    }

    // MARK: - Saving state

    /// Saves the current fingerprints and the updated dependency graph to disk.
    public func saveState(dependencyGraph: DependencyGraph) {
        let fm = FileManager.default

        do {
            if !fm.fileExists(atPath: cachePath) {
                try fm.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
            }

            // Save manifest
            let fingerprints = currentFingerprints.values.sorted(by: { $0.path < $1.path })
            let manifest = CacheManifest(
                version: 1,
                fingerprints: Array(fingerprints)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: URL(fileURLWithPath: cachePath + "/manifest.json"),
                options: .atomic
            )

            // Save dependency graph
            let depsData = try dependencyGraph.serialize()
            try depsData.write(
                to: URL(fileURLWithPath: cachePath + "/deps.json"),
                options: .atomic
            )
        } catch {
            // Cache save failure is non-fatal — next build will do a full compile.
            let message = "[IncrementalCompilationCache] Failed to save cache at '\(cachePath)': \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }

    /// Clears the entire cache directory.
    public func clearCache() {
        try? FileManager.default.removeItem(atPath: cachePath)
        previousFingerprints = [:]
        previousDependencyGraph = nil
        currentFingerprints = [:]
    }
}

// MARK: - Cache manifest model

struct CacheManifest: Codable {
    let version: Int
    let fingerprints: [FileFingerprint]
}
