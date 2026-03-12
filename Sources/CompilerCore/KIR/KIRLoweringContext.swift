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
    var nextLoopLabel: Int32 = 10000

    // MARK: - Module-Level State (accumulated across entire pass)

    private var functionDefaultArgumentsBySymbol: [SymbolID: [ExprID?]] = [:]
    private var pendingGeneratedCallableDeclIDs: [KIRDeclID] = []
    private var callableValueInfoByExprID: [KIRExprID: KIRCallableValueInfo] = [:]
    var syntheticLambdaSymbolsByExprID: [ExprID: SymbolID] = [:]
    private var syntheticObjectLiteralSymbolsByExprID: [ExprID: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString)] = [:]
    private var emittedObjectLiteralExprIDs: Set<ExprID> = []
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
        nextLoopLabel = 10000
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
