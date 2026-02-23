/// Caching layer for sema hot paths.
///
/// When the `-Xfrontend sema-cache` flag is active, ``TypeCheckSemaPassPhase``
/// creates a non-nil ``SemaCacheContext`` and threads it through the type-checking
/// pipeline.  The two primary caches are:
///
/// 1. **Scope lookup cache** – avoids repeated walks up the scope chain for the
///    same name in the same scope object.
/// 2. **Symbol lookup cache** – avoids repeated bounds-checked array accesses
///    for ``SymbolTable.symbol(_:)`` with the same ``SymbolID``.
///
/// When caching is disabled (the default), all call-sites receive `nil` and fall
/// back to the original uncached paths.
public final class SemaCacheContext {

    // MARK: - Scope lookup cache

    /// Keyed by the identity of the ``Scope`` object (via ``ObjectIdentifier``)
    /// and the interned name being looked up.
    private var scopeCache: [ObjectIdentifier: [InternedString: [SymbolID]]] = [:]

    /// Cached wrapper around ``Scope.lookup(_:)``.
    public func lookupInScope(_ name: InternedString, scope: Scope) -> [SymbolID] {
        let scopeKey = ObjectIdentifier(scope)
        if let nameCache = scopeCache[scopeKey], let cached = nameCache[name] {
            recordScopeHit()
            return cached
        }
        recordScopeMiss()
        let result = scope.lookup(name)
        scopeCache[scopeKey, default: [:]][name] = result
        return result
    }

    /// Invalidates all cached entries for a specific scope (e.g. after an insert).
    public func invalidateScope(_ scope: Scope) {
        scopeCache.removeValue(forKey: ObjectIdentifier(scope))
    }

    // MARK: - Symbol lookup cache

    /// Caches ``SymbolTable.symbol(_:)`` results to avoid repeated bounds checks.
    private var symbolCache: [SymbolID: SemanticSymbol] = [:]

    /// Set of IDs that have been queried but returned `nil` (invalid / out-of-bounds).
    private var symbolMissCache: Set<SymbolID> = []

    /// Cached wrapper around ``SymbolTable.symbol(_:)``.
    public func symbol(_ id: SymbolID, in table: SymbolTable) -> SemanticSymbol? {
        if let cached = symbolCache[id] {
            return cached
        }
        if symbolMissCache.contains(id) {
            return nil
        }
        let result = table.symbol(id)
        if let result {
            symbolCache[id] = result
        } else {
            symbolMissCache.insert(id)
        }
        return result
    }

    // MARK: - Overload resolution cache

    /// Cache key for ``OverloadResolver.resolveCall``.
    struct CallResolutionKey: Hashable {
        let candidates: [SymbolID]
        let calleeName: InternedString
        let argTypes: [TypeID]
        let argLabels: [InternedString?]
        let argIsSpread: [Bool]
        let explicitTypeArgs: [TypeID]
        let expectedType: TypeID?
        let implicitReceiverType: TypeID?
    }

    private var callResolutionCache: [CallResolutionKey: ResolvedCall] = [:]

    /// Returns a previously cached resolution result, or `nil` on a cache miss.
    func cachedCallResolution(for key: CallResolutionKey) -> ResolvedCall? {
        callResolutionCache[key]
    }

    /// Stores a resolution result in the cache.
    /// Results that contain a diagnostic are **not** cached because the diagnostic
    /// embeds source ranges from the specific call site.  Caching them would
    /// cause later call sites with the same key to receive diagnostics pointing
    /// at the wrong source location.
    func cacheCallResolution(_ result: ResolvedCall, for key: CallResolutionKey) {
        guard result.diagnostic == nil else { return }
        callResolutionCache[key] = result
    }

    /// Builds a ``CallResolutionKey`` from the parameters of ``OverloadResolver.resolveCall``.
    static func makeCallResolutionKey(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?
    ) -> CallResolutionKey {
        CallResolutionKey(
            candidates: candidates.sorted(by: { $0.rawValue < $1.rawValue }),
            calleeName: call.calleeName,
            argTypes: call.args.map(\.type),
            argLabels: call.args.map(\.label),
            argIsSpread: call.args.map(\.isSpread),
            explicitTypeArgs: call.explicitTypeArgs,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType
        )
    }

    // MARK: - Statistics (for testing / debugging)

    /// Number of scope lookup cache hits.
    public private(set) var scopeHits: Int = 0
    /// Number of scope lookup cache misses.
    public private(set) var scopeMisses: Int = 0
    /// Number of call resolution cache hits.
    public private(set) var callResolutionHits: Int = 0
    /// Number of call resolution cache misses.
    public private(set) var callResolutionMisses: Int = 0

    /// Increments scope hit counter (called internally).
    func recordScopeHit() { scopeHits += 1 }
    /// Increments scope miss counter (called internally).
    func recordScopeMiss() { scopeMisses += 1 }
    /// Increments call resolution hit counter.
    func recordCallResolutionHit() { callResolutionHits += 1 }
    /// Increments call resolution miss counter.
    func recordCallResolutionMiss() { callResolutionMisses += 1 }
}
