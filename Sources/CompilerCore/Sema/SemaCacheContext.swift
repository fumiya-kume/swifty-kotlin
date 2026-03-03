/// Caching layer for sema hot paths.
///
/// When the `-Xfrontend sema-cache` flag is active, ``TypeCheckSemaPassPhase``
/// creates a non-nil ``SemaCacheContext`` and threads it through the type-checking
/// pipeline.  This context currently provides:
///
/// 1. **Scope lookup cache** – avoids repeated walks up the scope chain for the
///    same name in the same scope object.  All results of ``Scope.lookup(_:)``
///    are cached until the enclosing scope is invalidated.
/// 2. **Symbol lookup cache** – avoids repeated bounds-checked array accesses
///    for ``SymbolTable.symbol(_:)`` with the same ``SymbolID``.  Both successful
///    lookups and known misses (invalid / out-of-bounds IDs) are cached.
/// 3. **Overload-resolution cache** – memoizes successful overload-resolution
///    results so that identical resolution requests do not need to be recomputed.
///    Only successful resolutions are cached; failing calls are never recorded.
///
/// When caching is disabled (the default), all call-sites receive `nil` and fall
/// back to the original uncached paths.
public final class SemaCacheContext {
    // MARK: - Scope lookup cache

    /// Keyed by the identity of the ``Scope`` object (via ``ObjectIdentifier``)
    /// and the interned name being looked up.
    ///
    /// The scope objects themselves are retained in ``scopeRetainer`` to prevent
    /// `ObjectIdentifier` reuse after deallocation.
    private var scopeCache: [ObjectIdentifier: [InternedString: [SymbolID]]] = [:]

    /// Retains scope objects whose identities are used as cache keys, preventing
    /// `ObjectIdentifier` reuse after a scope is deallocated.
    private var scopeRetainer: [ObjectIdentifier: Scope] = [:]

    /// Cached wrapper around ``Scope.lookup(_:)``.
    public func lookupInScope(_ name: InternedString, scope: Scope) -> [SymbolID] {
        let scopeKey = ObjectIdentifier(scope)
        if let nameCache = scopeCache[scopeKey], let cached = nameCache[name] {
            recordScopeHit()
            return cached
        }
        recordScopeMiss()
        let result = scope.lookup(name)
        scopeRetainer[scopeKey] = scope
        scopeCache[scopeKey, default: [:]][name] = result
        return result
    }

    /// Invalidates all cached entries for a specific scope (e.g. after an insert).
    public func invalidateScope(_ scope: Scope) {
        let key = ObjectIdentifier(scope)
        scopeCache.removeValue(forKey: key)
        scopeRetainer.removeValue(forKey: key)
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
    ///
    /// Includes the current ``FunctionSignature`` of each candidate so that
    /// mutations to signatures during type checking (e.g. when a function's
    /// return type is inferred from its body) cause a cache miss rather than
    /// returning stale results.
    struct CallResolutionKey: Hashable {
        let candidates: [SymbolID]
        let candidateSignatures: [FunctionSignature?]
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
    ///
    /// The ``symbols`` table is used to snapshot each candidate's current
    /// ``FunctionSignature`` so the key becomes invalid when a signature is
    /// mutated during type checking.
    static func makeCallResolutionKey(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        symbols: SymbolTable
    ) -> CallResolutionKey {
        let sorted = candidates.sorted(by: { $0.rawValue < $1.rawValue })
        return CallResolutionKey(
            candidates: sorted,
            candidateSignatures: sorted.map { symbols.functionSignature(for: $0) },
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
    func recordScopeHit() {
        scopeHits += 1
    }

    /// Increments scope miss counter (called internally).
    func recordScopeMiss() {
        scopeMisses += 1
    }

    /// Increments call resolution hit counter.
    func recordCallResolutionHit() {
        callResolutionHits += 1
    }

    /// Increments call resolution miss counter.
    func recordCallResolutionMiss() {
        callResolutionMisses += 1
    }
}
