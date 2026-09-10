
struct TypeInferenceContext: CustomStringConvertible {
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
    /// Stack of labels attached to enclosing lambda literals.
    /// Used by `return@label` to verify that the label references a valid lambda.
    var lambdaLabelStack: [InternedString]
    /// Number of lambda bodies enclosing the expression currently being inferred.
    /// An unlabeled return inside such a body is a non-local return and is checked
    /// against the surrounding named function's return type rather than the
    /// lambda's predicate/result type.
    var lambdaDepth: Int = 0
    /// Return type of the nearest named function body. This remains unchanged
    /// while entering lambda literals so non-local return values are checked
    /// against the actual return target.
    var enclosingFunctionReturnType: TypeID?
    /// When set, the specified block expression exports its local bindings to
    /// the outer locals map. Used for do-while body-to-condition visibility.
    var exportBlockLocalsForExpr: ExprID?
    var flowState: DataFlowState
    let currentFileID: FileID
    var currentDeclSymbol: SymbolID?
    /// When set, the symbol of the property/val whose initializer expression is
    /// currently being type-checked. A bare name reference that resolves back to
    /// this same symbol is a self-referential read before the property has ever
    /// been initialized (DEBT-SEMA-003), e.g. `val cyclic: List<*> = listOf(cyclic)`.
    /// Scoped to just the initializer expression — not carried into getter/setter
    /// bodies, where reading the property's own name is a normal (if recursive)
    /// property access rather than a use-before-init.
    var initializingPropertySymbol: SymbolID?
    var enclosingClassSymbol: SymbolID?
    let visibilityChecker: VisibilityChecker
    var outerReceiverTypes: [(label: InternedString, type: TypeID)]
    /// Context receiver types available to `contextOf<A>()` in the current lambda body.
    var contextReceiverTypes: [TypeID] = []
    /// When true, the current scope is a builder DSL lambda body (STDLIB-002).
    /// Used to scope `append`/`add`/`put` fallback resolution.
    var isBuilderLambdaScope: Bool = false
    /// When true, platform-type warnings for `return` expressions should be suppressed.
    /// Set for functions whose return type is inferred (not user-declared).
    var suppressPlatformReturnWarning: Bool = false
    /// The specific builder kind for this scope (STDLIB-002).
    /// Used to restrict member function resolution to the correct kind.
    var builderKind: BuilderDSLKind?
    /// When true, the current scope is a `flow { ... }` builder lambda body.
    /// Used to resolve unqualified `emit(...)` fallback.
    var isFlowBuilderLambdaScope: Bool = false
    /// When true, the current scope is a coroutine builder lambda body.
    /// The lambda keeps the existing no-receiver ABI, but unqualified
    /// `CoroutineScope` extension calls still resolve against the ambient scope.
    var isCoroutineBuilderLambdaScope: Bool = false
    /// When true, assigning to an immutable member property is treated as
    /// initialization rather than reassignment. Used for `init {}` and
    /// constructor bodies.
    var allowsValPropertyInitialization: Bool = false
    /// Sema cache context for hot-path caching.  `nil` when caching is disabled.
    let semaCacheContext: SemaCacheContext?
    /// Mirrors Kotlin's `-Xnew-inference`.
    let useNewInference: Bool
    /// Mirrors Kotlin's `-Xunrestricted-builder-inference`.
    let useUnrestrictedBuilderInference: Bool
    /// Mirrors Kotlin's `ProperTypeInferenceConstraintsProcessing`.
    let useProperTypeInferenceConstraintsProcessing: Bool
    /// Marker annotations accepted through compiler-wide `-opt-in=<fqName>`.
    let globalOptInMarkerNames: [String]
    /// Set of DslMarker annotation FQ names active on the current implicit receiver.
    /// When a nested lambda introduces a receiver whose class carries the same
    /// DslMarker annotation as an outer receiver, the outer receiver is hidden
    /// from implicit resolution.
    var activeDslMarkerAnnotations: Set<String> = []
    func with(implicitReceiverType newType: TypeID?) -> TypeInferenceContext {
        var copy = self
        copy.implicitReceiverType = newType
        // Update active DslMarker annotations for the new receiver.
        if let newType {
            copy.activeDslMarkerAnnotations = copy.collectDslMarkerAnnotations(for: newType)
        } else {
            copy.activeDslMarkerAnnotations = []
        }
        return copy
    }

    func withLambdaLabel(_ label: InternedString) -> TypeInferenceContext {
        var copy = self
        copy.lambdaLabelStack = lambdaLabelStack + [label]
        return copy
    }

    func enteringLambdaBody() -> TypeInferenceContext {
        var copy = self
        copy.lambdaDepth += 1
        return copy
    }

    func hasLambdaLabel(_ label: InternedString) -> Bool {
        lambdaLabelStack.contains(label)
    }

    func with(currentDeclSymbol newSymbol: SymbolID?) -> TypeInferenceContext {
        var copy = self; copy.currentDeclSymbol = newSymbol; return copy
    }

    func with(initializingPropertySymbol newSymbol: SymbolID?) -> TypeInferenceContext {
        var copy = self; copy.initializingPropertySymbol = newSymbol; return copy
    }

    func copying(
        scope: Scope? = nil,
        implicitReceiverType: TypeID?? = nil,
        loopDepth: Int? = nil,
        loopLabelStack: [InternedString]? = nil,
        lambdaLabelStack: [InternedString]? = nil,
        lambdaDepth: Int? = nil,
        enclosingFunctionReturnType: TypeID?? = nil,
        exportBlockLocalsForExpr: ExprID?? = nil,
        flowState: DataFlowState? = nil,
        currentDeclSymbol: SymbolID?? = nil,
        enclosingClassSymbol: SymbolID?? = nil,
        outerReceiverTypes: [(label: InternedString, type: TypeID)]? = nil,
        contextReceiverTypes: [TypeID]? = nil
    ) -> TypeInferenceContext {
        var copy = self
        if let scope { copy.scope = scope }
        if let implicitReceiverType {
            copy.implicitReceiverType = implicitReceiverType
            // Update active DslMarker annotations when the receiver changes.
            if let newType = implicitReceiverType {
                copy.activeDslMarkerAnnotations = copy.collectDslMarkerAnnotations(for: newType)
            } else {
                copy.activeDslMarkerAnnotations = []
            }
        }
        if let loopDepth { copy.loopDepth = loopDepth }
        if let loopLabelStack { copy.loopLabelStack = loopLabelStack }
        if let lambdaLabelStack { copy.lambdaLabelStack = lambdaLabelStack }
        if let lambdaDepth { copy.lambdaDepth = lambdaDepth }
        if let enclosingFunctionReturnType {
            copy.enclosingFunctionReturnType = enclosingFunctionReturnType
        }
        if let exportBlockLocalsForExpr { copy.exportBlockLocalsForExpr = exportBlockLocalsForExpr }
        if let flowState { copy.flowState = flowState }
        if let currentDeclSymbol { copy.currentDeclSymbol = currentDeclSymbol }
        if let enclosingClassSymbol { copy.enclosingClassSymbol = enclosingClassSymbol }
        if let outerReceiverTypes { copy.outerReceiverTypes = outerReceiverTypes }
        if let contextReceiverTypes { copy.contextReceiverTypes = contextReceiverTypes }
        return copy
    }

    func with(contextReceiverTypes newTypes: [TypeID]) -> TypeInferenceContext {
        var copy = self
        copy.contextReceiverTypes = newTypes
        return copy
    }

    func withOuterReceiver(label: InternedString, type: TypeID) -> TypeInferenceContext {
        var copy = self
        copy.outerReceiverTypes = outerReceiverTypes + [(label: label, type: type)]
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

    /// Looks up a symbol, using the sema cache when available.
    func cachedSymbol(_ id: SymbolID) -> SemanticSymbol? {
        if let cache = semaCacheContext {
            return cache.symbol(id, in: sema.symbols)
        }
        return sema.symbols.symbol(id)
    }

    /// Performs a scope lookup, using the sema cache when available.
    ///
    /// `expect`/`actual` pairs are intentionally allowed to coexist in the same
    /// scope (KSwiftK has no separate common/platform module compilation), so a
    /// linked `expect` declaration is filtered out here once its `actual` is
    /// known. Without this, every expression-level reference to the pair would
    /// see two candidates with an identical shape: call resolution reports a
    /// false ambiguous-overload, and name resolution binds arbitrarily to
    /// whichever declaration happens to come first.
    func cachedScopeLookup(_ name: InternedString) -> [SymbolID] {
        let results: [SymbolID] = if let cache = semaCacheContext {
            cache.lookupInScope(name, scope: scope)
        } else {
            scope.lookup(name)
        }
        return results.filter { !isExpectDeclarationSupersededByActual($0) }
    }

    private func isExpectDeclarationSupersededByActual(_ id: SymbolID) -> Bool {
        guard let symbol = cachedSymbol(id), symbol.flags.contains(.expectDeclaration) else {
            return false
        }
        return sema.symbols.actualSymbol(for: id) != nil
    }

    /// Collects the FQ names of all @DslMarker meta-annotations that apply to
    /// the given type.  A type carries a DslMarker if it is a class/interface
    /// annotated with an annotation class that is itself annotated with
    /// `@DslMarker`.
    func collectDslMarkerAnnotations(for typeID: TypeID) -> Set<String> {
        let nonNull = sema.types.makeNonNullable(typeID)
        guard let classType = resolveClassType(nonNull, sema: sema) else {
            return []
        }
        let classSymbol = classType.classSymbol
        let annotations = sema.symbols.annotations(for: classSymbol)
        var dslMarkers: Set<String> = []
        for annotation in annotations {
            // Check if the annotation class itself is annotated with @DslMarker.
            // First, look up the annotation class symbol by its FQ name.
            let annotationFQName = annotation.annotationFQName
            if isDslMarkerAnnotation(annotationFQName) {
                dslMarkers.insert(annotationFQName)
            }
        }
        return dslMarkers
    }

    /// Returns true if the annotation with the given FQ name is a DslMarker
    /// annotation — i.e. the annotation class itself is annotated with @DslMarker.
    private func isDslMarkerAnnotation(_ annotationFQName: String) -> Bool {
        // Look up the annotation class by its simple or qualified name in the symbol table.
        let parts = annotationFQName.split(separator: ".").map { String($0) }
        let internedParts = parts.map { interner.intern($0) }

        // Try qualified lookup first
        if let annotationSymbol = sema.symbols.lookup(fqName: internedParts) {
            let metaAnnotations = sema.symbols.annotations(for: annotationSymbol)
            for meta in metaAnnotations {
                // swiftlint:disable:next for_where
                if KnownCompilerAnnotation.dslMarker.matches(meta.annotationFQName) {
                    return true
                }
            }
        }
        // Try simple name lookup (single segment)
        if parts.count == 1 {
            let simpleName = interner.intern(parts[0])
            let candidates = scope.lookup(simpleName)
            for candidateID in candidates {
                guard let candidateSymbol = sema.symbols.symbol(candidateID),
                      candidateSymbol.kind == .annotationClass else {
                    continue
                }
                let metaAnnotations = sema.symbols.annotations(for: candidateID)
                for meta in metaAnnotations {
                    // swiftlint:disable:next for_where
                    if KnownCompilerAnnotation.dslMarker.matches(meta.annotationFQName) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Returns true if accessing the given candidate symbol through the scope
    /// chain is blocked by @DslMarker restrictions.  A member symbol is blocked
    /// when its owner class/interface carries a DslMarker annotation that also
    /// applies to the current implicit receiver, and the owner is NOT the
    /// current implicit receiver itself.
    func isCandidateBlockedByDslMarker(_ candidateID: SymbolID) -> Bool {
        guard !activeDslMarkerAnnotations.isEmpty else {
            return false
        }
        guard let parentID = sema.symbols.parentSymbol(for: candidateID) else {
            return false
        }
        // The parent must be a class, interface, or object to carry DslMarker.
        guard let parentSymbol = sema.symbols.symbol(parentID),
              parentSymbol.kind == .class || parentSymbol.kind == .interface || parentSymbol.kind == .object
        else {
            return false
        }
        // If the parent IS the current implicit receiver's class, no restriction.
        if let receiverType = implicitReceiverType {
            let nonNull = sema.types.makeNonNullable(receiverType)
            if case let .classType(classType) = sema.types.kind(of: nonNull),
               classType.classSymbol == parentID
            {
                return false
            }
        }
        // Check if the parent class's DslMarker annotations overlap with the
        // active ones from the current implicit receiver.
        let parentType = sema.types.make(.classType(ClassType(
            classSymbol: parentID, args: [], nullability: .nonNull
        )))
        let parentDslMarkers = collectDslMarkerAnnotations(for: parentType)
        return !activeDslMarkerAnnotations.isDisjoint(with: parentDslMarkers)
    }

    var description: String {
        return "\(useNewInference) \(useUnrestrictedBuilderInference) \(useProperTypeInferenceConstraintsProcessing)"
    }
}
