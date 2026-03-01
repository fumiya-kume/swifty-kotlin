import Foundation

/// Caches library manifest info and parsed metadata records keyed by path + mtime,
/// and memoizes type signature parse results keyed by signature string.
///
/// This avoids redundant file I/O and parsing when the same `.kklib` directory is
/// referenced across compilations or when multiple symbols share the same type signature.
///
/// - Important: This class is **not** thread-safe. It is designed for use within a
///   single compilation session on one thread — the same threading model used by the
///   rest of the Sema pipeline.
public final class LibraryMetadataCache {
    public init() {}

    // MARK: - Manifest cache (libraryDir → single entry with mtime + target)

    private struct ManifestCacheEntry {
        let mtimeNanos: Int64
        let targetString: String
        let info: DataFlowSemaPhase.LibraryManifestInfo
    }

    /// Stores at most one entry per `libraryDir`. When the file's mtime changes or
    /// the compilation target differs, the old entry is replaced — preventing unbounded growth.
    private var manifestCache: [String: ManifestCacheEntry] = [:]

    /// Returns a cached manifest info if the library directory has not been modified
    /// since the last read and the compilation target matches, or `nil` on cache miss.
    func cachedManifestInfo(libraryDir: String, target: TargetTriple) -> DataFlowSemaPhase.LibraryManifestInfo? {
        let manifestPath = URL(fileURLWithPath: libraryDir)
            .appendingPathComponent("manifest.json").path
        let mtime = Self.fileMtimeNanos(path: manifestPath)
        let targetStr = "\(target.arch)-\(target.vendor)-\(target.os)"
        guard let entry = manifestCache[libraryDir],
              entry.mtimeNanos == mtime,
              entry.targetString == targetStr
        else {
            return nil
        }
        return entry.info
    }

    /// Stores a manifest info result for the given library directory.
    /// Replaces any previous entry for the same `libraryDir`.
    func cacheManifestInfo(_ info: DataFlowSemaPhase.LibraryManifestInfo, libraryDir: String, target: TargetTriple) {
        let manifestPath = URL(fileURLWithPath: libraryDir)
            .appendingPathComponent("manifest.json").path
        let mtime = Self.fileMtimeNanos(path: manifestPath)
        let targetStr = "\(target.arch)-\(target.vendor)-\(target.os)"
        manifestCache[libraryDir] = ManifestCacheEntry(mtimeNanos: mtime, targetString: targetStr, info: info)
    }

    // MARK: - Metadata records cache (metadataPath → single entry with mtime + interner)

    private struct MetadataCacheEntry {
        let mtimeNanos: Int64
        let records: [DataFlowSemaPhase.ImportedLibrarySymbolRecord]
    }

    /// `ImportedLibrarySymbolRecord` contains `InternedString` values whose IDs are
    /// only meaningful for the `StringInterner` that created them. We track the current
    /// interner and auto-clear the metadata cache when a different interner is seen.
    private var currentInternerID: ObjectIdentifier?

    /// Stores at most one entry per `metadataPath`. When the file's mtime changes,
    /// the old entry is replaced — preventing unbounded growth.
    private var metadataCache: [String: MetadataCacheEntry] = [:]

    /// Returns cached metadata records if the metadata file has not been modified
    /// since the last parse and the same `StringInterner` is in use, or `nil` on cache miss.
    func cachedMetadataRecords(metadataPath: String, interner: StringInterner) -> [DataFlowSemaPhase.ImportedLibrarySymbolRecord]? {
        let intID = ObjectIdentifier(interner)
        if currentInternerID != intID {
            return nil // different interner — treat as miss
        }
        let mtime = Self.fileMtimeNanos(path: metadataPath)
        guard let entry = metadataCache[metadataPath],
              entry.mtimeNanos == mtime
        else {
            return nil
        }
        return entry.records
    }

    /// Stores parsed metadata records for the given metadata file path.
    /// Replaces any previous entry for the same `metadataPath`.
    /// Automatically clears the metadata cache when a different `StringInterner` is encountered.
    func cacheMetadataRecords(
        _ records: [DataFlowSemaPhase.ImportedLibrarySymbolRecord],
        metadataPath: String,
        interner: StringInterner
    ) {
        let intID = ObjectIdentifier(interner)
        if currentInternerID != intID {
            metadataCache.removeAll()
            currentInternerID = intID
        }
        let mtime = Self.fileMtimeNanos(path: metadataPath)
        metadataCache[metadataPath] = MetadataCacheEntry(mtimeNanos: mtime, records: records)
    }

    // MARK: - Type signature memoization (signature string + TypeSystem identity)

    /// TypeID values are indices into a specific TypeSystem's internal storage,
    /// and class-type signatures embed SymbolIDs from a specific SymbolTable.
    /// We must scope the signature cache per both TypeSystem and SymbolTable
    /// instance to avoid returning stale IDs.
    private var currentTypeSystemID: ObjectIdentifier?
    private var currentSymbolTableID: ObjectIdentifier?
    private var signatureCache: [String: TypeID?] = [:]

    /// Returns a cached type ID for the given encoded signature string.
    ///
    /// The cache is automatically invalidated when a different `TypeSystem` or
    /// `SymbolTable` is passed.
    ///
    /// The return type is a *double optional*:
    /// - `nil` (outer optional) means there is no cached entry for this signature
    ///   under the current `TypeSystem`/`SymbolTable` (cache miss).
    /// - `.some(nil)` means there is a cached entry whose value is `nil`, i.e. a previous
    ///   attempt to parse the signature failed or produced no `TypeID`.
    /// - `.some(.some(id))` means there is a cached successful parse result.
    func cachedSignature(_ signature: String, types: TypeSystem, symbols: SymbolTable) -> TypeID?? {
        let tsID = ObjectIdentifier(types)
        let stID = ObjectIdentifier(symbols)
        if currentTypeSystemID != tsID || currentSymbolTableID != stID {
            return nil // different TypeSystem or SymbolTable — treat as miss
        }
        guard let entry = signatureCache[signature] else {
            return nil // cache miss — outer optional is nil
        }
        return entry // cache hit — may be .some(nil) for previously-failed parses
    }

    /// Stores a type signature parse result (including `nil` for failures).
    /// Automatically clears the cache when a different `TypeSystem` or `SymbolTable` is encountered.
    func cacheSignature(_ result: TypeID?, for signature: String, types: TypeSystem, symbols: SymbolTable) {
        let tsID = ObjectIdentifier(types)
        let stID = ObjectIdentifier(symbols)
        if currentTypeSystemID != tsID || currentSymbolTableID != stID {
            signatureCache.removeAll()
            currentTypeSystemID = tsID
            currentSymbolTableID = stID
        }
        signatureCache[signature] = result
    }

    // MARK: - Statistics

    /// Number of manifest cache entries.
    public var manifestCacheCount: Int {
        manifestCache.count
    }

    /// Number of metadata record cache entries.
    public var metadataCacheCount: Int {
        metadataCache.count
    }

    /// Number of cached type signature entries.
    public var signatureCacheCount: Int {
        signatureCache.count
    }

    // MARK: - Helpers

    private static func fileMtimeNanos(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date
        else {
            return 0
        }
        return Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}
