import Foundation

/// Caches library manifest info and parsed metadata records keyed by path + mtime,
/// and memoizes type signature parse results keyed by signature string.
///
/// This avoids redundant file I/O and parsing when the same `.kklib` directory is
/// referenced across compilations or when multiple symbols share the same type signature.
public final class LibraryMetadataCache {

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

    // MARK: - Metadata records cache (path + mtime)

    private struct MetadataCacheKey: Hashable {
        let metadataPath: String
        let mtimeNanos: Int64
    }

    private var metadataCache: [MetadataCacheKey: [DataFlowSemaPassPhase.ImportedLibrarySymbolRecord]] = [:]

    /// Returns cached metadata records if the metadata file has not been modified
    /// since the last parse, or `nil` on cache miss.
    func cachedMetadataRecords(metadataPath: String) -> [DataFlowSemaPassPhase.ImportedLibrarySymbolRecord]? {
        let mtime = Self.fileMtimeNanos(path: metadataPath)
        let key = MetadataCacheKey(metadataPath: metadataPath, mtimeNanos: mtime)
        return metadataCache[key]
    }

    /// Stores parsed metadata records for the given metadata file path.
    func cacheMetadataRecords(
        _ records: [DataFlowSemaPassPhase.ImportedLibrarySymbolRecord],
        metadataPath: String
    ) {
        let mtime = Self.fileMtimeNanos(path: metadataPath)
        let key = MetadataCacheKey(metadataPath: metadataPath, mtimeNanos: mtime)
        metadataCache[key] = records
    }

    // MARK: - Type signature memoization (signature string key)

    private var signatureCache: [String: TypeID?] = [:]

    /// Returns a cached type ID for the given encoded signature string, or `nil` on miss.
    /// Note: the cached value itself may be `Optional<TypeID>.some(nil)` when the previous
    /// parse returned nil (malformed signature). Use `hasCachedSignature` to distinguish.
    func cachedSignature(_ signature: String) -> TypeID?? {
        guard let entry = signatureCache[signature] else {
            return nil  // cache miss — outer optional is nil
        }
        return entry  // cache hit — may be .some(nil) for previously-failed parses
    }

    /// Stores a type signature parse result (including `nil` for failures).
    func cacheSignature(_ result: TypeID?, for signature: String) {
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
