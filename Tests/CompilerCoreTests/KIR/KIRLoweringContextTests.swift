@testable import CompilerCore
import XCTest

final class KIRLoweringContextTests: XCTestCase {
    var ctx: KIRLoweringContext!

    override func setUp() {
        super.setUp()
        ctx = KIRLoweringContext()
    }

    // MARK: - Scope Management: saveScope / restoreScope

    func testSaveScopeReturnsSnapshotOfCurrentState() {
        ctx.localValuesBySymbol[SymbolID(rawValue: 1)] = KIRExprID(rawValue: 10)
        ctx.currentImplicitReceiverExprID = KIRExprID(rawValue: 5)
        ctx.currentImplicitReceiverSymbol = SymbolID(rawValue: 2)
        ctx.loopControlStack = [(continueLabel: 100, breakLabel: 200, name: nil)]
        ctx.nextLoopLabel = 20000

        let snapshot = ctx.saveScope()

        XCTAssertEqual(snapshot.localValuesBySymbol[SymbolID(rawValue: 1)], KIRExprID(rawValue: 10))
        XCTAssertEqual(snapshot.currentImplicitReceiverExprID, KIRExprID(rawValue: 5))
        XCTAssertEqual(snapshot.currentImplicitReceiverSymbol, SymbolID(rawValue: 2))
        XCTAssertEqual(snapshot.loopControlStack.count, 1)
        XCTAssertEqual(snapshot.loopControlStack[0].continueLabel, 100)
        XCTAssertEqual(snapshot.loopControlStack[0].breakLabel, 200)
        XCTAssertNil(snapshot.loopControlStack[0].name)
        XCTAssertEqual(snapshot.nextLoopLabel, 20000)
    }

    func testRestoreScopeRevertsAllScopeProperties() {
        let snapshot = ctx.saveScope()
        ctx.localValuesBySymbol[SymbolID(rawValue: 99)] = KIRExprID(rawValue: 99)
        ctx.currentImplicitReceiverExprID = KIRExprID(rawValue: 7)
        ctx.currentImplicitReceiverSymbol = SymbolID(rawValue: 3)
        ctx.loopControlStack = [(continueLabel: 1, breakLabel: 2, name: nil)]
        ctx.nextLoopLabel = 50000

        ctx.restoreScope(snapshot)

        XCTAssertTrue(ctx.localValuesBySymbol.isEmpty)
        XCTAssertNil(ctx.currentImplicitReceiverExprID)
        XCTAssertNil(ctx.currentImplicitReceiverSymbol)
        XCTAssertTrue(ctx.loopControlStack.isEmpty)
        XCTAssertEqual(ctx.nextLoopLabel, 10000)
    }

    func testRestoreScopePreservesSnapshotValues() {
        ctx.localValuesBySymbol[SymbolID(rawValue: 1)] = KIRExprID(rawValue: 42)
        ctx.nextLoopLabel = 15000
        let snapshot = ctx.saveScope()

        ctx.resetScopeForFunction()
        XCTAssertTrue(ctx.localValuesBySymbol.isEmpty)

        ctx.restoreScope(snapshot)
        XCTAssertEqual(ctx.localValuesBySymbol[SymbolID(rawValue: 1)], KIRExprID(rawValue: 42))
        XCTAssertEqual(ctx.nextLoopLabel, 15000)
    }

    // MARK: - Scope Management: withNewScope

    func testWithNewScopeResetsAndRestoresAfterBlock() throws {
        ctx.localValuesBySymbol[SymbolID(rawValue: 5)] = KIRExprID(rawValue: 5)
        ctx.nextLoopLabel = 20000

        try ctx.withNewScope {
            XCTAssertTrue(ctx.localValuesBySymbol.isEmpty, "Scope inside block should be reset")
            XCTAssertEqual(ctx.nextLoopLabel, 10000, "Label should reset inside block")
            ctx.localValuesBySymbol[SymbolID(rawValue: 9)] = KIRExprID(rawValue: 9)
        }

        XCTAssertEqual(ctx.localValuesBySymbol[SymbolID(rawValue: 5)], KIRExprID(rawValue: 5),
                       "Original localValues should be restored")
        XCTAssertNil(ctx.localValuesBySymbol[SymbolID(rawValue: 9)], "Inner scope changes should not leak")
        XCTAssertEqual(ctx.nextLoopLabel, 20000, "Label should be restored after block")
    }

    func testNestedWithNewScopeRestoresCorrectly() throws {
        ctx.nextLoopLabel = 30000

        try ctx.withNewScope {
            XCTAssertEqual(ctx.nextLoopLabel, 10000)
            ctx.nextLoopLabel = 40000

            try ctx.withNewScope {
                XCTAssertEqual(ctx.nextLoopLabel, 10000)
            }

            XCTAssertEqual(ctx.nextLoopLabel, 40000, "Inner withNewScope should restore to outer value")
        }

        XCTAssertEqual(ctx.nextLoopLabel, 30000, "Outer withNewScope should restore to original value")
    }

    func testWithNewScopeRethrowsErrors() {
        struct TestError: Error {}
        XCTAssertThrowsError(
            try ctx.withNewScope { throw TestError() }
        )
    }

    // MARK: - Scope Management: resetScopeForFunction

    func testResetScopeForFunctionClearsAllScopeProperties() {
        ctx.localValuesBySymbol[SymbolID(rawValue: 1)] = KIRExprID(rawValue: 1)
        ctx.currentImplicitReceiverExprID = KIRExprID(rawValue: 3)
        ctx.currentImplicitReceiverSymbol = SymbolID(rawValue: 2)
        ctx.loopControlStack = [(continueLabel: 10, breakLabel: 20, name: nil), (continueLabel: 30, breakLabel: 40, name: nil)]
        ctx.nextLoopLabel = 99999

        ctx.resetScopeForFunction()

        XCTAssertTrue(ctx.localValuesBySymbol.isEmpty)
        XCTAssertNil(ctx.currentImplicitReceiverExprID)
        XCTAssertNil(ctx.currentImplicitReceiverSymbol)
        XCTAssertTrue(ctx.loopControlStack.isEmpty)
        XCTAssertEqual(ctx.nextLoopLabel, 10000)
    }

    // MARK: - Label Allocation

    func testMakeLoopLabelStartsAt10000() {
        XCTAssertEqual(ctx.makeLoopLabel(), 10000)
    }

    func testMakeLoopLabelIncrements() {
        let first = ctx.makeLoopLabel()
        let second = ctx.makeLoopLabel()
        let third = ctx.makeLoopLabel()
        XCTAssertEqual(first, 10000)
        XCTAssertEqual(second, 10001)
        XCTAssertEqual(third, 10002)
    }

    func testMakeLoopLabelResetsAfterResetScope() {
        _ = ctx.makeLoopLabel()
        _ = ctx.makeLoopLabel()
        XCTAssertEqual(ctx.nextLoopLabel, 10002)

        ctx.resetScopeForFunction()
        XCTAssertEqual(ctx.makeLoopLabel(), 10000)
    }

    func testLabelAllocationInsideWithNewScopeResetsTo10000() throws {
        _ = ctx.makeLoopLabel()
        _ = ctx.makeLoopLabel()

        var labelInsideScope: Int32 = -1
        try ctx.withNewScope {
            labelInsideScope = ctx.makeLoopLabel()
        }

        XCTAssertEqual(labelInsideScope, 10000, "Labels inside withNewScope should start at 10000")
        XCTAssertEqual(ctx.nextLoopLabel, 10002, "Labels should be restored after withNewScope")
    }

    // MARK: - Callable Lowering Scope

    func testBeginCallableLoweringScopeClearsPendingDecls() {
        ctx.pendingGeneratedCallableDeclIDs = [KIRDeclID(rawValue: 1), KIRDeclID(rawValue: 2)]
        ctx.beginCallableLoweringScope()
        XCTAssertTrue(ctx.pendingGeneratedCallableDeclIDs.isEmpty)
    }

    func testDrainGeneratedCallableDeclsReturnsAndClears() {
        ctx.pendingGeneratedCallableDeclIDs = [KIRDeclID(rawValue: 10), KIRDeclID(rawValue: 20)]
        let drained = ctx.drainGeneratedCallableDecls()
        XCTAssertEqual(drained.map(\.rawValue), [10, 20])
        XCTAssertTrue(ctx.pendingGeneratedCallableDeclIDs.isEmpty)
    }

    func testDrainGeneratedCallableDeclsReturnsEmptyWhenNothingPending() {
        let drained = ctx.drainGeneratedCallableDecls()
        XCTAssertTrue(drained.isEmpty)
    }

    func testRegisterCallableValueStoresInfo() {
        let interner = StringInterner()
        let exprID = KIRExprID(rawValue: 7)
        let symbol = SymbolID(rawValue: 3)
        let callee = interner.intern("myLambda")
        let captureArgs = [KIRExprID(rawValue: 1), KIRExprID(rawValue: 2)]

        ctx.registerCallableValue(exprID, symbol: symbol, callee: callee, captureArguments: captureArgs)

        let info = ctx.callableValueInfoByExprID[exprID]
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.symbol, symbol)
        XCTAssertEqual(info?.callee, callee)
        XCTAssertEqual(info?.captureArguments, captureArgs)
    }

    func testRegisterCallableValueOverwritesPrevious() {
        let interner = StringInterner()
        let exprID = KIRExprID(rawValue: 7)
        let callee1 = interner.intern("first")
        let callee2 = interner.intern("second")

        ctx.registerCallableValue(exprID, symbol: SymbolID(rawValue: 1), callee: callee1, captureArguments: [])
        ctx.registerCallableValue(exprID, symbol: SymbolID(rawValue: 2), callee: callee2, captureArguments: [])

        XCTAssertEqual(ctx.callableValueInfoByExprID[exprID]?.callee, callee2)
    }

    // MARK: - Synthetic Symbol Management

    func testSyntheticLambdaSymbolReturnsSameIDForSameExprID() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)

        let exprID = ExprID(rawValue: 1)
        let id1 = ctx.syntheticLambdaSymbol(for: exprID)
        let id2 = ctx.syntheticLambdaSymbol(for: exprID)

        XCTAssertEqual(id1, id2)
    }

    func testSyntheticLambdaSymbolReturnsDifferentIDsForDifferentExprIDs() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)

        let id1 = ctx.syntheticLambdaSymbol(for: ExprID(rawValue: 1))
        let id2 = ctx.syntheticLambdaSymbol(for: ExprID(rawValue: 2))

        XCTAssertNotEqual(id1, id2)
    }

    func testAllocateSyntheticGeneratedSymbolIncrementsSequentially() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)
        let base = ctx.nextSyntheticLambdaSymbolRawValue

        let s1 = ctx.allocateSyntheticGeneratedSymbol()
        let s2 = ctx.allocateSyntheticGeneratedSymbol()

        XCTAssertEqual(s1.rawValue, base)
        XCTAssertEqual(s2.rawValue, base + 1)
    }

    func testInitializeSyntheticLambdaSymbolAllocatorUsesAtLeast1() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)
        XCTAssertGreaterThanOrEqual(ctx.nextSyntheticLambdaSymbolRawValue, 1)
    }

    func testInitializeSyntheticLambdaSymbolAllocatorBasedOnSymbolCount() {
        let (semaModule, symbols, _, interner) = makeSemaModule()
        // Define a symbol so count > 0
        _ = symbols.define(
            kind: .function,
            name: interner.intern("foo"),
            fqName: [interner.intern("foo")],
            declSite: nil,
            visibility: .public
        )
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)
        XCTAssertGreaterThanOrEqual(ctx.nextSyntheticLambdaSymbolRawValue, Int32(symbols.count))
    }

    // MARK: - Module State Reset

    func testResetModuleStateClearsAllModuleLevelCollections() {
        let interner = StringInterner()
        let exprID = KIRExprID(rawValue: 1)
        ctx.pendingGeneratedCallableDeclIDs = [KIRDeclID(rawValue: 1)]
        ctx.registerCallableValue(exprID, symbol: SymbolID(rawValue: 1), callee: interner.intern("x"), captureArguments: [])
        ctx.syntheticLambdaSymbolsByExprID[ExprID(rawValue: 1)] = SymbolID(rawValue: 1)
        ctx.syntheticObjectLiteralSymbolsByExprID[ExprID(rawValue: 2)] = (
            nominalSymbol: SymbolID(rawValue: 2),
            constructorSymbol: SymbolID(rawValue: 3),
            constructorName: interner.intern("Obj")
        )
        ctx.emittedObjectLiteralExprIDs.insert(ExprID(rawValue: 3))

        ctx.resetModuleState()

        XCTAssertTrue(ctx.pendingGeneratedCallableDeclIDs.isEmpty)
        XCTAssertTrue(ctx.callableValueInfoByExprID.isEmpty)
        XCTAssertTrue(ctx.syntheticLambdaSymbolsByExprID.isEmpty)
        XCTAssertTrue(ctx.syntheticObjectLiteralSymbolsByExprID.isEmpty)
        XCTAssertTrue(ctx.emittedObjectLiteralExprIDs.isEmpty)
    }
}
