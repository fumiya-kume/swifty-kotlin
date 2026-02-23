import Foundation

/// Manages the on-disk cache for incremental compilation.
///
/// The cache directory layout is:
/// ```
/// <cachePath>/
///   manifest.json       — file fingerprints from the previous build
///   deps.json           — dependency graph (symbol ↔ file relationships)
///   per-file/
///     <hash>.kirbin     — serialized per-file frontend results
/// ```
public final class IncrementalCompilationCache {

    /// Root directory of the cache.
    public let cachePath: String

    /// Fingerprints from the *previous* successful compilation.
    private var previousFingerprints: [String: FileFingerprint] = [:]

    /// Dependency graph from the *previous* successful compilation.
    private var previousDependencyGraph: DependencyGraph = DependencyGraph()

    /// Fingerprints computed for the *current* compilation inputs.
    private var currentFingerprints: [String: FileFingerprint] = [:]

    public init(cachePath: String) {
        self.cachePath = cachePath
    }

    // MARK: - Loading previous state

    /// Loads the manifest and dependency graph from the cache directory.
    /// If the cache doesn't exist or is corrupt, starts fresh.
    public func loadPreviousState() {
        let fm = FileManager.default
        let manifestPath = cachePath + "/manifest.json"
        let depsPath = cachePath + "/deps.json"

        if fm.fileExists(atPath: manifestPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) {
            let decoder = JSONDecoder()
            if let manifest = try? decoder.decode(CacheManifest.self, from: data) {
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
        // also invalidate the cache (but they won't be in allPaths, so their
        // dependents will be caught by the dependency graph).
        return changed
    }

    /// Computes the full recompilation set using the dependency graph.
    /// Returns `nil` if no cache is available (full build needed).
    public func recompilationSet(allPaths: [String]) -> Set<String>? {
        if previousFingerprints.isEmpty {
            // No previous build — full build needed.
            return nil
        }

        let changed = changedFiles(allPaths: allPaths)
        if changed.isEmpty {
            return Set()
        }

        let recompFiles = previousDependencyGraph.recompilationSet(
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
    public var dependencyGraph: DependencyGraph {
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
            try manifestData.write(to: URL(fileURLWithPath: cachePath + "/manifest.json"))

            // Save dependency graph
            let depsData = try dependencyGraph.serialize()
            try depsData.write(to: URL(fileURLWithPath: cachePath + "/deps.json"))
        } catch {
            // Cache save failure is non-fatal — next build will do a full compile.
        }
    }

    /// Clears the entire cache directory.
    public func clearCache() {
        try? FileManager.default.removeItem(atPath: cachePath)
        previousFingerprints = [:]
        previousDependencyGraph = DependencyGraph()
        currentFingerprints = [:]
    }
}

// MARK: - Cache manifest model

struct CacheManifest: Codable {
    let version: Int
    let fingerprints: [FileFingerprint]
}
