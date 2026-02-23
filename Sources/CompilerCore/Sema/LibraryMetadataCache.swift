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

    // MARK: - Manifest cache (path + mtime)

    private struct ManifestCacheKey: Hashable {
        let libraryDir: String
        let mtimeNanos: Int64
    }

    private var manifestCache: [ManifestCacheKey: DataFlowSemaPassPhase.LibraryManifestInfo] = [:]

    /// Returns a cached manifest info if the library directory has not been modified
    /// since the last read, or `nil` on cache miss.
    func cachedManifestInfo(libraryDir: String) -> DataFlowSemaPassPhase.LibraryManifestInfo? {
        let manifestPath = URL(fileURLWithPath: libraryDir)
            .appendingPathComponent("manifest.json").path
        let mtime = Self.fileMtimeNanos(path: manifestPath)
        let key = ManifestCacheKey(libraryDir: libraryDir, mtimeNanos: mtime)
        return manifestCache[key]
    }

    /// Stores a manifest info result for the given library directory.
    func cacheManifestInfo(_ info: DataFlowSemaPassPhase.LibraryManifestInfo, libraryDir: String) {
        let manifestPath = URL(fileURLWithPath: libraryDir)
            .appendingPathComponent("manifest.json").path
        let mtime = Self.fileMtimeNanos(path: manifestPath)
        let key = ManifestCacheKey(libraryDir: libraryDir, mtimeNanos: mtime)
        manifestCache[key] = info
    }

    // MARK: - Metadata records cache (path + mtime + StringInterner identity)

    private struct MetadataCacheKey: Hashable {
        let metadataPath: String
        let mtimeNanos: Int64
    }

    /// `ImportedLibrarySymbolRecord` contains `InternedString` values whose IDs are
    /// only meaningful for the `StringInterner` that created them. We track the current
    /// interner and auto-clear the metadata cache when a different interner is seen.
    private var currentInternerID: ObjectIdentifier?
    private var metadataCache: [MetadataCacheKey: [DataFlowSemaPassPhase.ImportedLibrarySymbolRecord]] = [:]

    /// Returns cached metadata records if the metadata file has not been modified
    /// since the last parse and the same `StringInterner` is in use, or `nil` on cache miss.
    func cachedMetadataRecords(metadataPath: String, interner: StringInterner) -> [DataFlowSemaPassPhase.ImportedLibrarySymbolRecord]? {
        let intID = ObjectIdentifier(interner)
        if currentInternerID != intID {
            return nil  // different interner — treat as miss
        }
        let mtime = Self.fileMtimeNanos(path: metadataPath)
        let key = MetadataCacheKey(metadataPath: metadataPath, mtimeNanos: mtime)
        return metadataCache[key]
    }

    /// Stores parsed metadata records for the given metadata file path.
    /// Automatically clears the metadata cache when a different `StringInterner` is encountered.
    func cacheMetadataRecords(
        _ records: [DataFlowSemaPassPhase.ImportedLibrarySymbolRecord],
        metadataPath: String,
        interner: StringInterner
    ) {
        let intID = ObjectIdentifier(interner)
        if currentInternerID != intID {
            metadataCache.removeAll()
            currentInternerID = intID
        }
        let mtime = Self.fileMtimeNanos(path: metadataPath)
        let key = MetadataCacheKey(metadataPath: metadataPath, mtimeNanos: mtime)
        metadataCache[key] = records
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
    /// The cache is automatically invalidated when a different `TypeSystem` is passed.
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
            return nil  // different TypeSystem or SymbolTable — treat as miss
        }
        guard let entry = signatureCache[signature] else {
            return nil  // cache miss — outer optional is nil
        }
        return entry  // cache hit — may be .some(nil) for previously-failed parses
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
    public var manifestCacheCount: Int { manifestCache.count }

    /// Number of metadata record cache entries.
    public var metadataCacheCount: Int { metadataCache.count }

    /// Number of cached type signature entries.
    public var signatureCacheCount: Int { signatureCache.count }

    // MARK: - Helpers

    private static func fileMtimeNanos(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return 0
        }
        return Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}
