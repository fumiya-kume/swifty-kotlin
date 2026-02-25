import Foundation

// Internal visibility is required for cross-file extension decomposition.
struct TypeInferenceContext {
    let ast: ASTModule
    let sema: SemaModule
    let semaCtx: SemaModule
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    var scope: Scope
    var implicitReceiverType: TypeID?
    var loopDepth: Int
    var loopLabelStack: [InternedString]
    var flowState: DataFlowState
    let currentFileID: FileID
    var enclosingClassSymbol: SymbolID?
    let visibilityChecker: VisibilityChecker
    var outerReceiverTypes: [(label: InternedString, type: TypeID)]
    /// Sema cache context for hot-path caching.  `nil` when caching is disabled.
    let semaCacheContext: SemaCacheContext?

    func with(scope newScope: Scope) -> TypeInferenceContext {
        var copy = self; copy.scope = newScope; return copy
    }

    func with(implicitReceiverType newType: TypeID?) -> TypeInferenceContext {
        var copy = self; copy.implicitReceiverType = newType; return copy
    }

    func with(loopDepth newDepth: Int) -> TypeInferenceContext {
        var copy = self; copy.loopDepth = newDepth; return copy
    }

    func with(flowState newState: DataFlowState) -> TypeInferenceContext {
        var copy = self; copy.flowState = newState; return copy
    }

    func with(enclosingClassSymbol newSymbol: SymbolID?) -> TypeInferenceContext {
        var copy = self; copy.enclosingClassSymbol = newSymbol; return copy
    }

    func copying(
        scope: Scope? = nil,
        implicitReceiverType: TypeID?? = nil,
        loopDepth: Int? = nil,
        loopLabelStack: [InternedString]? = nil,
        flowState: DataFlowState? = nil,
        enclosingClassSymbol: SymbolID?? = nil,
        outerReceiverTypes: [(label: InternedString, type: TypeID)]? = nil
    ) -> TypeInferenceContext {
        var copy = self
        if let scope { copy.scope = scope }
        if let implicitReceiverType { copy.implicitReceiverType = implicitReceiverType }
        if let loopDepth { copy.loopDepth = loopDepth }
        if let loopLabelStack { copy.loopLabelStack = loopLabelStack }
        if let flowState { copy.flowState = flowState }
        if let enclosingClassSymbol { copy.enclosingClassSymbol = enclosingClassSymbol }
        if let outerReceiverTypes { copy.outerReceiverTypes = outerReceiverTypes }
        return copy
    }

    func withOuterReceiver(label: InternedString, type: TypeID) -> TypeInferenceContext {
        var copy = self
        copy.outerReceiverTypes = self.outerReceiverTypes + [(label: label, type: type)]
        return copy
    }

    func resolveQualifiedThis(label: InternedString) -> TypeID? {
        for entry in outerReceiverTypes.reversed() where entry.label == label {
            return entry.type
        }
        return nil
    }

    func filterByVisibility(_ candidates: [SymbolID]) -> (visible: [SymbolID], invisible: [SemanticSymbol]) {
        var visible: [SymbolID] = []
        var invisible: [SemanticSymbol] = []
        for candidate in candidates {
            guard let symbol = cachedSymbol(candidate) else { continue }
            if visibilityChecker.isAccessible(symbol, fromFile: currentFileID, enclosingClass: enclosingClassSymbol) {
                visible.append(candidate)
            } else {
                invisible.append(symbol)
            }
        }
        return (visible, invisible)
    }

    // MARK: - Cached helpers

    /// Looks up a symbol, using the sema cache when available.
    func cachedSymbol(_ id: SymbolID) -> SemanticSymbol? {
        if let cache = semaCacheContext {
            return cache.symbol(id, in: sema.symbols)
        }
        return sema.symbols.symbol(id)
    }

    /// Performs a scope lookup, using the sema cache when available.
    func cachedScopeLookup(_ name: InternedString) -> [SymbolID] {
        if let cache = semaCacheContext {
            return cache.lookupInScope(name, scope: scope)
        }
        return scope.lookup(name)
    }
}
