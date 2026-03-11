import Foundation

/// Tracks symbol-level dependencies between source files for incremental compilation.
///
/// Each file *provides* (defines) a set of symbol names and *depends on* (references)
/// a set of symbol names.  When a file changes, every other file that depends on any
/// symbol provided by the changed file is added to the recompilation set.
public final class DependencyGraph: Codable {
    // MARK: - Storage

    private var providedSymbols: [String: Set<String>] = [:]

    private var dependedSymbols: [String: Set<String>] = [:]

    public init() {}

    // MARK: - Mutation

    public func recordProvided(filePath: String, symbols: Set<String>) {
        providedSymbols[filePath] = symbols
    }

    public func recordDepended(filePath: String, symbols: Set<String>) {
        dependedSymbols[filePath] = symbols
    }

    public func clearFile(_ filePath: String) {
        providedSymbols.removeValue(forKey: filePath)
        dependedSymbols.removeValue(forKey: filePath)
    }

    // MARK: - Query

    /// Given a set of files that changed, compute the full set of files that need
    /// recompilation.  This includes:
    /// 1. The changed files themselves.
    /// 2. Any file that depends on a symbol provided by a changed file (transitively).
    ///
    /// The result is deterministic (sorted).
    public func recompilationSet(changedFiles: Set<String>, allFiles: [String]) -> [String] {
        if changedFiles.isEmpty {
            return []
        }

        var invalidatedSymbols = Set<String>()
        for changed in changedFiles {
            if let provided = providedSymbols[changed] {
                invalidatedSymbols.formUnion(provided)
            }
        }

        var affected = changedFiles
        var frontier = changedFiles
        var visited = changedFiles

        // Iterate to handle transitive dependencies: if file A depends on file B's
        // symbol and file B is newly added to the recompilation set, file A's
        // provided symbols may also need to invalidate further files.
        while !frontier.isEmpty {
            var nextFrontier = Set<String>()
            for filePath in allFiles {
                guard !visited.contains(filePath) else { continue }
                guard let depended = dependedSymbols[filePath] else { continue }
                if !depended.isDisjoint(with: invalidatedSymbols) {
                    affected.insert(filePath)
                    nextFrontier.insert(filePath)
                    // The newly-affected file's provided symbols may cause
                    // further invalidation.
                    if let provided = providedSymbols[filePath] {
                        invalidatedSymbols.formUnion(provided)
                    }
                }
            }
            visited.formUnion(nextFrontier)
            frontier = nextFrontier
        }

        return allFiles.filter { affected.contains($0) }
    }

    public var trackedFiles: [String] {
        let allKeys = Set(providedSymbols.keys).union(dependedSymbols.keys)
        return allKeys.sorted()
    }

    public func provided(by filePath: String) -> Set<String> {
        providedSymbols[filePath] ?? []
    }

    public func depended(by filePath: String) -> Set<String> {
        dependedSymbols[filePath] ?? []
    }

    // MARK: - Serialization

    public func serialize() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public static func deserialize(from data: Data) throws -> DependencyGraph {
        let decoder = JSONDecoder()
        return try decoder.decode(DependencyGraph.self, from: data)
    }
}
