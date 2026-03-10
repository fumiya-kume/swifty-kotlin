import Foundation

/// Holds all mutable state for the KIR lowering pass.
///
/// Centralises the 12 mutable instance properties that were previously scattered
/// across `BuildKIRPhase` and its extensions. Provides structured scope management
/// helpers (`saveScope`, `restoreScope`, `resetScopeForFunction`, `withNewScope`)
/// so that each call site can choose the appropriate granularity.
final class KIRLoweringContext {
    // MARK: - Scope State (saved/restored per function/lambda)

    var localValuesBySymbol: [SymbolID: KIRExprID] = [:]
    var currentImplicitReceiverExprID: KIRExprID?
    var currentImplicitReceiverSymbol: SymbolID?
    var currentFunctionSymbol: SymbolID?
    var loopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)] = []
    var nextLoopLabel: Int32 = 10000

    // MARK: - Module-Level State (accumulated across entire pass)

    var functionDefaultArgumentsBySymbol: [SymbolID: [ExprID?]] = [:]
    var pendingGeneratedCallableDeclIDs: [KIRDeclID] = []
    var callableValueInfoByExprID: [KIRExprID: KIRCallableValueInfo] = [:]
    var syntheticLambdaSymbolsByExprID: [ExprID: SymbolID] = [:]
    var syntheticObjectLiteralSymbolsByExprID: [ExprID: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString)] = [:]
    var emittedObjectLiteralExprIDs: Set<ExprID> = []
    var nextSyntheticLambdaSymbolRawValue: Int32 = 1

    /// Companion object initializer functions registered during class lowering.
    /// These are called in order during module initialization.
    var companionInitializerFunctions: [(symbol: SymbolID, name: InternedString)] = []

    // MARK: - Structured Scope Management

    struct ScopeSnapshot {
        let localValuesBySymbol: [SymbolID: KIRExprID]
        let currentImplicitReceiverExprID: KIRExprID?
        let currentImplicitReceiverSymbol: SymbolID?
        let currentFunctionSymbol: SymbolID?
        let loopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)]
        let nextLoopLabel: Int32
    }

    func saveScope() -> ScopeSnapshot {
        ScopeSnapshot(
            localValuesBySymbol: localValuesBySymbol,
            currentImplicitReceiverExprID: currentImplicitReceiverExprID,
            currentImplicitReceiverSymbol: currentImplicitReceiverSymbol,
            currentFunctionSymbol: currentFunctionSymbol,
            loopControlStack: loopControlStack,
            nextLoopLabel: nextLoopLabel
        )
    }

    func restoreScope(_ snapshot: ScopeSnapshot) {
        localValuesBySymbol = snapshot.localValuesBySymbol
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

    func resetModuleState() {
        pendingGeneratedCallableDeclIDs.removeAll(keepingCapacity: true)
        callableValueInfoByExprID.removeAll(keepingCapacity: true)
        syntheticLambdaSymbolsByExprID.removeAll(keepingCapacity: true)
        syntheticObjectLiteralSymbolsByExprID.removeAll(keepingCapacity: true)
        emittedObjectLiteralExprIDs.removeAll(keepingCapacity: true)
        companionInitializerFunctions.removeAll(keepingCapacity: true)
    }
}
