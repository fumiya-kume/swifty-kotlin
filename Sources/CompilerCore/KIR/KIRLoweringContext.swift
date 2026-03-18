import Foundation

/// Centralises the 12 mutable instance properties that were previously scattered
/// across `BuildKIRPhase` and its extensions. Provides structured scope management
/// helpers (`saveScope`, `restoreScope`, `resetScopeForFunction`, `withNewScope`)
/// so that each call site can choose the appropriate granularity.
final class KIRLoweringContext {
    // MARK: - Scope State (saved/restored per function/lambda)

    var localValuesBySymbol: [SymbolID: KIRExprID] = [:]
    /// Lambda param name → symbol for resolving nameRef when identifierSymbols is unbound
    /// (e.g. collection HOF lambdas inferred via fallback).
    var lambdaParamNameToSymbol: [InternedString: SymbolID] = [:]
    var currentImplicitReceiverExprID: KIRExprID?
    var currentImplicitReceiverSymbol: SymbolID?
    var currentFunctionSymbol: SymbolID?
    var loopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)] = []
    /// Stack of enclosing finally block entries.
    /// Each entry records the finally block expression ID and the loop-control-stack
    /// depth at the time the try-finally scope was entered.  This depth is used to
    /// determine whether a `break`/`continue` exits the try scope (and should inline
    /// the finally block) or stays within the same try scope (and should skip it).
    ///
    /// When a `return`, `break`, or `continue` is lowered inside a try-finally,
    /// the compiler inlines the finally block code before the control-flow transfer
    /// so that finally semantics are preserved (CODE-001).
    ///
    /// Use `pushFinallyBlock`, `popFinallyBlock`, `enclosingFinallyBlocks`,
    /// `enclosingFinallyBlocksForControlFlow`, and `withFinallyStackDepth`
    /// instead of mutating this property directly.
    private(set) var finallyBlockStack: [(exprID: ExprID, loopDepth: Int)] = []
    var nextLoopLabel: Int32 = 10000

    // MARK: - Module-Level State (accumulated across entire pass)

    private var functionDefaultArgumentsBySymbol: [SymbolID: [ExprID?]] = [:]
    var pendingGeneratedCallableDeclIDs: [KIRDeclID] = []
    var callableValueInfoByExprID: [KIRExprID: KIRCallableValueInfo] = [:]
    var syntheticLambdaSymbolsByExprID: [ExprID: SymbolID] = [:]
    var syntheticObjectLiteralSymbolsByExprID: [ExprID: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString)] = [:]
    var emittedObjectLiteralExprIDs: Set<ExprID> = []
    var nextSyntheticLambdaSymbolRawValue: Int32 = 1

    /// Companion object initializer functions registered during class lowering.
    /// These are called in order during module initialization.
    private var companionInitializerFunctions: [(symbol: SymbolID, name: InternedString)] = []

    // MARK: - Structured Scope Management

    struct ScopeSnapshot {
        let localValuesBySymbol: [SymbolID: KIRExprID]
        let lambdaParamNameToSymbol: [InternedString: SymbolID]
        let currentImplicitReceiverExprID: KIRExprID?
        let currentImplicitReceiverSymbol: SymbolID?
        let currentFunctionSymbol: SymbolID?
        let loopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)]
        let finallyBlockStack: [(exprID: ExprID, loopDepth: Int)]
        let nextLoopLabel: Int32
    }

    func saveScope() -> ScopeSnapshot {
        ScopeSnapshot(
            localValuesBySymbol: localValuesBySymbol,
            lambdaParamNameToSymbol: lambdaParamNameToSymbol,
            currentImplicitReceiverExprID: currentImplicitReceiverExprID,
            currentImplicitReceiverSymbol: currentImplicitReceiverSymbol,
            currentFunctionSymbol: currentFunctionSymbol,
            loopControlStack: loopControlStack,
            finallyBlockStack: finallyBlockStack,
            nextLoopLabel: nextLoopLabel
        )
    }

    func restoreScope(_ snapshot: ScopeSnapshot) {
        localValuesBySymbol = snapshot.localValuesBySymbol
        lambdaParamNameToSymbol = snapshot.lambdaParamNameToSymbol
        currentImplicitReceiverExprID = snapshot.currentImplicitReceiverExprID
        currentImplicitReceiverSymbol = snapshot.currentImplicitReceiverSymbol
        currentFunctionSymbol = snapshot.currentFunctionSymbol
        loopControlStack = snapshot.loopControlStack
        finallyBlockStack = snapshot.finallyBlockStack
        nextLoopLabel = snapshot.nextLoopLabel
    }

    /// Execute `body` in a fresh scope, restoring the previous scope on return.
    /// Replaces the manual save/defer/restore pattern used in 6+ sites.
    func withNewScope<T>(_ body: () throws -> T) rethrows -> T {
        let snapshot = saveScope()
        defer { restoreScope(snapshot) }
        resetScopeForFunction()
        return try body()
    }

    func resetScopeForFunction() {
        localValuesBySymbol.removeAll(keepingCapacity: true)
        lambdaParamNameToSymbol.removeAll(keepingCapacity: true)
        currentImplicitReceiverExprID = nil
        currentImplicitReceiverSymbol = nil
        currentFunctionSymbol = nil
        loopControlStack.removeAll(keepingCapacity: true)
        finallyBlockStack.removeAll(keepingCapacity: true)
        nextLoopLabel = 10000
    }

    func localValue(for symbol: SymbolID) -> KIRExprID? {
        localValuesBySymbol[symbol]
    }

    func setLocalValue(_ exprID: KIRExprID, for symbol: SymbolID) {
        localValuesBySymbol[symbol] = exprID
    }

    func clearLocalValue(for symbol: SymbolID) {
        localValuesBySymbol.removeValue(forKey: symbol)
    }

    func allLocalValues() -> [SymbolID: KIRExprID] {
        localValuesBySymbol
    }

    func lambdaParamSymbol(named name: InternedString) -> SymbolID? {
        lambdaParamNameToSymbol[name]
    }

    func registerLambdaParam(symbol: SymbolID, forName name: InternedString) {
        lambdaParamNameToSymbol[name] = symbol
    }

    func activeImplicitReceiverExprID() -> KIRExprID? {
        currentImplicitReceiverExprID
    }

    func activeImplicitReceiverSymbol() -> SymbolID? {
        currentImplicitReceiverSymbol
    }

    func activeImplicitReceiver() -> (symbol: SymbolID, exprID: KIRExprID)? {
        guard let symbol = currentImplicitReceiverSymbol,
              let exprID = currentImplicitReceiverExprID
        else {
            return nil
        }
        return (symbol: symbol, exprID: exprID)
    }

    func setImplicitReceiver(symbol: SymbolID, exprID: KIRExprID) {
        currentImplicitReceiverSymbol = symbol
        currentImplicitReceiverExprID = exprID
    }

    func clearImplicitReceiver() {
        currentImplicitReceiverSymbol = nil
        currentImplicitReceiverExprID = nil
    }

    func restoreImplicitReceiver(symbol: SymbolID?, exprID: KIRExprID?) {
        if let symbol, let exprID {
            setImplicitReceiver(symbol: symbol, exprID: exprID)
        } else {
            clearImplicitReceiver()
        }
    }

    func activeFunctionSymbol() -> SymbolID? {
        currentFunctionSymbol
    }

    func setCurrentFunctionSymbol(_ symbol: SymbolID?) {
        currentFunctionSymbol = symbol
    }

    func pushLoopControl(continueLabel: Int32, breakLabel: Int32, name: InternedString?) {
        loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel, name: name))
    }

    // MARK: - Finally Block Stack (CODE-001)

    func pushFinallyBlock(_ exprID: ExprID) {
        finallyBlockStack.append((exprID: exprID, loopDepth: loopControlStack.count))
    }

    @discardableResult
    func popFinallyBlock() -> ExprID? {
        finallyBlockStack.popLast()?.exprID
    }

    /// Returns the current stack of enclosing finally block expression IDs (outermost first).
    func enclosingFinallyBlocks() -> [ExprID] {
        finallyBlockStack.map(\.exprID)
    }

    /// Returns enclosing finally block expression IDs that should be inlined
    /// for a `break` or `continue` targeting the loop at `targetLoopDepth`.
    ///
    /// A finally block should be inlined only when the break/continue exits
    /// its enclosing try scope.  A finally entry with `loopDepth > targetLoopDepth`
    /// means the try was entered when more loops were on the stack than the
    /// target loop's position, i.e. the try is nested inside the target loop,
    /// so the break/continue exits the try scope and must run finally.
    ///
    /// Entries with `loopDepth <= targetLoopDepth` mean the try encloses the
    /// target loop, so break/continue stays within the try scope and the
    /// finally block should NOT be inlined.
    func enclosingFinallyBlocksForBreakOrContinue(targetLoopDepth: Int) -> [ExprID] {
        finallyBlockStack
            .filter { $0.loopDepth > targetLoopDepth }
            .map(\.exprID)
    }

    /// Returns the loop-control-stack depth for the loop targeted by a `break`.
    /// This is the index of the target loop entry in `loopControlStack`.
    func breakTargetLoopDepth(for name: InternedString?) -> Int {
        if let name {
            if let idx = loopControlStack.lastIndex(where: { $0.name == name }) {
                return idx
            }
        }
        return max(0, loopControlStack.count - 1)
    }

    /// Returns the loop-control-stack depth for the loop targeted by a `continue`.
    func continueTargetLoopDepth(for name: InternedString?) -> Int {
        breakTargetLoopDepth(for: name)
    }

    /// Temporarily trim the finally block stack to `depth` entries, execute
    /// `body`, then restore the stack to its previous state.  Uses suffix
    /// save/restore to avoid copy-on-write of the full array (CODE-001).
    func withFinallyStackDepth<T>(_ depth: Int, _ body: () throws -> T) rethrows -> T {
        let removedSuffix = Array(finallyBlockStack[depth...])
        finallyBlockStack.removeSubrange(depth..<finallyBlockStack.count)
        defer { finallyBlockStack.append(contentsOf: removedSuffix) }
        return try body()
    }

    @discardableResult
    func popLoopControl() -> (continueLabel: Int32, breakLabel: Int32, name: InternedString?)? {
        loopControlStack.popLast()
    }

    func breakLabel(for name: InternedString?) -> Int32? {
        if let name {
            return loopControlStack.last(where: { $0.name == name })?.breakLabel
        }
        return loopControlStack.last?.breakLabel
    }

    func continueLabel(for name: InternedString?) -> Int32? {
        if let name {
            return loopControlStack.last(where: { $0.name == name })?.continueLabel
        }
        return loopControlStack.last?.continueLabel
    }

    // MARK: - Label Allocation

    func makeLoopLabel() -> Int32 {
        let label = nextLoopLabel
        nextLoopLabel += 1
        return label
    }

    // MARK: - Callable Lowering Scope

    func beginCallableLoweringScope() {
        pendingGeneratedCallableDeclIDs.removeAll(keepingCapacity: true)
    }

    func drainGeneratedCallableDecls() -> [KIRDeclID] {
        let generated = pendingGeneratedCallableDeclIDs
        pendingGeneratedCallableDeclIDs.removeAll(keepingCapacity: true)
        return generated
    }

    func appendGeneratedCallableDecl(_ declID: KIRDeclID) {
        pendingGeneratedCallableDeclIDs.append(declID)
    }

    func registerCallableValue(
        _ exprID: KIRExprID,
        symbol: SymbolID,
        callee: InternedString,
        captureArguments: [KIRExprID],
        hasClosureParam: Bool = false
    ) {
        callableValueInfoByExprID[exprID] = KIRCallableValueInfo(
            symbol: symbol,
            callee: callee,
            captureArguments: captureArguments,
            hasClosureParam: hasClosureParam
        )
    }

    func callableValueInfo(for exprID: KIRExprID) -> KIRCallableValueInfo? {
        callableValueInfoByExprID[exprID]
    }

    func setFunctionDefaultArguments(_ mapping: [SymbolID: [ExprID?]]) {
        functionDefaultArgumentsBySymbol = mapping
    }

    func defaultArguments(for symbol: SymbolID) -> [ExprID?]? {
        functionDefaultArgumentsBySymbol[symbol]
    }

    // MARK: - Synthetic Symbol Management

    func initializeSyntheticLambdaSymbolAllocator(sema: SemaModule) {
        let base = max(Int64(1), Int64(sema.symbols.count))
        if base > Int64(Int32.max) {
            nextSyntheticLambdaSymbolRawValue = Int32.max
        } else {
            nextSyntheticLambdaSymbolRawValue = Int32(base)
        }
    }

    func syntheticLambdaSymbol(for exprID: ExprID) -> SymbolID {
        if let existing = syntheticLambdaSymbolsByExprID[exprID] {
            return existing
        }
        let symbol = allocateSyntheticGeneratedSymbol()
        syntheticLambdaSymbolsByExprID[exprID] = symbol
        return symbol
    }

    func allocateSyntheticGeneratedSymbol() -> SymbolID {
        SymbolID(rawValue: nextSyntheticLambdaSymbolRawID())
    }

    func syntheticObjectLiteralSymbols(
        for exprID: ExprID
    ) -> (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString)? {
        syntheticObjectLiteralSymbolsByExprID[exprID]
    }

    func registerSyntheticObjectLiteralSymbols(
        _ symbols: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString),
        for exprID: ExprID
    ) {
        syntheticObjectLiteralSymbolsByExprID[exprID] = symbols
    }

    @discardableResult
    func markObjectLiteralEmitted(_ exprID: ExprID) -> Bool {
        emittedObjectLiteralExprIDs.insert(exprID).inserted
    }

    private func nextSyntheticLambdaSymbolRawID() -> Int32 {
        precondition(
            nextSyntheticLambdaSymbolRawValue < Int32.max,
            "Exhausted synthetic symbol IDs for lambda lowering."
        )
        let allocated = nextSyntheticLambdaSymbolRawValue
        nextSyntheticLambdaSymbolRawValue += 1
        return allocated
    }

    // MARK: - Reset

    func registerCompanionInitializer(symbol: SymbolID, name: InternedString) {
        companionInitializerFunctions.append((symbol: symbol, name: name))
    }

    func allCompanionInitializers() -> [(symbol: SymbolID, name: InternedString)] {
        companionInitializerFunctions
    }

    func resetModuleState() {
        pendingGeneratedCallableDeclIDs.removeAll(keepingCapacity: true)
        callableValueInfoByExprID.removeAll(keepingCapacity: true)
        syntheticLambdaSymbolsByExprID.removeAll(keepingCapacity: true)
        syntheticObjectLiteralSymbolsByExprID.removeAll(keepingCapacity: true)
        emittedObjectLiteralExprIDs.removeAll(keepingCapacity: true)
        companionInitializerFunctions.removeAll(keepingCapacity: true)
    }
}
