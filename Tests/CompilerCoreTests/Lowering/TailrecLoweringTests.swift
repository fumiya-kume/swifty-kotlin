@testable import CompilerCore
import Foundation
import XCTest

final class TailrecLoweringTests: XCTestCase {
    /// Thrown after `XCTFail` in helpers that need to stop execution.
    private struct TestFailure: Error {}

    // MARK: - Test Helpers

    /// Create a `KIRContext` with the given module name and a shared interner.
    /// Avoids repeating `CompilerOptions` / `DiagnosticEngine` / temp-path
    /// boilerplate across every test.
    private func makeKIRContext(
        moduleName: String,
        interner: StringInterner
    ) -> KIRContext {
        KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )
    }

    /// Build a single-function `KIRModule`, run `TailrecLoweringPass`, and
    /// return the lowered function.
    @discardableResult
    private func runTailrecPass(
        function: KIRFunction,
        arena: KIRArena,
        moduleName: String,
        interner: StringInterner
    ) throws -> KIRFunction {
        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])],
            arena: arena
        )
        let ctx = makeKIRContext(moduleName: moduleName, interner: interner)
        try TailrecLoweringPass().run(module: module, ctx: ctx)
        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected lowered function")
            throw TestFailure()
        }
        return lowered
    }

    // MARK: - Unit Tests (KIR level)

    /// Verify that a tailrec function's self-recursive call + returnValue
    /// is replaced by parameter copy + jump to loop head.
    func testTailrecRewritesSelfRecursiveCallToLoop() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let fnSymbol = SymbolID(rawValue: 100)
        let paramN = SymbolID(rawValue: 101)
        let paramAcc = SymbolID(rawValue: 102)

        let intType = types.make(.primitive(.int, .nonNull))
        let nExpr = arena.appendExpr(.symbolRef(paramN))
        let accExpr = arena.appendExpr(.symbolRef(paramAcc))
        let zeroExpr = arena.appendExpr(.intLiteral(0))
        let oneExpr = arena.appendExpr(.intLiteral(1))
        let subResult = arena.appendExpr(.temporary(0))
        let mulResult = arena.appendExpr(.temporary(1))
        let callResult = arena.appendExpr(.temporary(2))

        let tailrecFunction = KIRFunction(
            symbol: fnSymbol,
            name: interner.intern("fact"),
            params: [KIRParameter(symbol: paramN, type: intType), KIRParameter(symbol: paramAcc, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                // if (n == 0) jump to L1
                .jumpIfEqual(lhs: nExpr, rhs: zeroExpr, target: 1),
                // recursive case: fact(n - 1, n * acc)
                .binary(op: .subtract, lhs: nExpr, rhs: oneExpr, result: subResult),
                .binary(op: .multiply, lhs: nExpr, rhs: accExpr, result: mulResult),
                .call(
                    symbol: fnSymbol,
                    callee: interner.intern("fact"),
                    arguments: [subResult, mulResult],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
                // base case
                .label(1),
                .returnValue(accExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false,
            isTailrec: true
        )

        let lowered = try runTailrecPass(
            function: tailrecFunction, arena: arena,
            moduleName: "TailrecTest", interner: interner
        )

        // The loop-head label should be present.
        let hasLoopLabel = lowered.body.contains { instruction in
            if case let .label(id) = instruction {
                return id == tailrecLoopLabelBase
            }
            return false
        }
        XCTAssertTrue(hasLoopLabel, "Expected loop-head label L\(tailrecLoopLabelBase)")

        // The jump back to loop head should be present.
        let hasJumpBack = lowered.body.contains { instruction in
            if case let .jump(target) = instruction {
                return target == tailrecLoopLabelBase
            }
            return false
        }
        XCTAssertTrue(hasJumpBack, "Expected jump back to loop head")

        // The self-recursive call should be gone.
        let hasSelfCall = lowered.body.contains { instruction in
            if case let .call(sym, _, _, _, _, _, _, _) = instruction, sym == fnSymbol {
                return true
            }
            return false
        }
        XCTAssertFalse(hasSelfCall, "Self-recursive call should have been eliminated")

        // There should be copy instructions for parameter reassignment.
        let copyCount = lowered.body.filter { instruction in
            if case .copy = instruction { return true }
            return false
        }.count
        XCTAssertGreaterThanOrEqual(copyCount, 2, "Expected parameter reassignment copies")
    }

    func testTailrecDoesNotReuseBranchLocalCanonicalParameterExprs() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let fnSymbol = SymbolID(rawValue: 300)
        let paramN = SymbolID(rawValue: 301)
        let paramAcc = SymbolID(rawValue: 302)

        let intType = types.make(.primitive(.int, .nonNull))
        let zeroExpr = arena.appendExpr(.intLiteral(0))
        let oneExpr = arena.appendExpr(.intLiteral(1))
        let recursiveArg0 = arena.appendExpr(.temporary(0))
        let recursiveArg1 = arena.appendExpr(.temporary(1))
        let callResult = arena.appendExpr(.temporary(2))
        let lateParamExpr = arena.appendExpr(.symbolRef(paramN))
        let lateAccExpr = arena.appendExpr(.symbolRef(paramAcc))

        let tailrecFunction = KIRFunction(
            symbol: fnSymbol,
            name: interner.intern("factLike"),
            params: [KIRParameter(symbol: paramN, type: intType), KIRParameter(symbol: paramAcc, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                .jumpIfEqual(lhs: recursiveArg0, rhs: zeroExpr, target: 1),
                .binary(op: .subtract, lhs: recursiveArg0, rhs: oneExpr, result: recursiveArg0),
                .copy(from: recursiveArg1, to: recursiveArg1),
                .call(
                    symbol: fnSymbol,
                    callee: interner.intern("factLike"),
                    arguments: [recursiveArg0, recursiveArg1],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
                .label(1),
                .constValue(result: lateParamExpr, value: .symbolRef(paramN)),
                .constValue(result: lateAccExpr, value: .symbolRef(paramAcc)),
                .returnValue(lateAccExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false,
            isTailrec: true
        )

        let lowered = try runTailrecPass(
            function: tailrecFunction, arena: arena,
            moduleName: "TailrecBranchExprs", interner: interner
        )

        let reusedLateBranchExpr = lowered.body.contains { instruction in
            guard case let .copy(_, to) = instruction else {
                return false
            }
            return to == lateParamExpr || to == lateAccExpr
        }
        XCTAssertFalse(
            reusedLateBranchExpr,
            "Tailrec lowering must not reuse canonical parameter exprs that appear after the loop header."
        )
    }

    /// Verify that non-tailrec functions are NOT rewritten.
    func testNonTailrecFunctionIsNotModified() {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let fnSymbol = SymbolID(rawValue: 200)
        let callResult = arena.appendExpr(.temporary(0))

        let nonTailrecFunction = KIRFunction(
            symbol: fnSymbol,
            name: interner.intern("regular"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .beginBlock,
                .call(
                    symbol: fnSymbol,
                    callee: interner.intern("regular"),
                    arguments: [],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false,
            isTailrec: false // NOT tailrec
        )

        let fnID = arena.appendDecl(.function(nonTailrecFunction))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])],
            arena: arena
        )
        let ctx = makeKIRContext(moduleName: "NonTailrecTest", interner: interner)

        // shouldRun should return false.
        XCTAssertFalse(TailrecLoweringPass().shouldRun(module: module, ctx: ctx))
    }

    /// LOWER-005: Verify that a tailrec function's self-recursive call
    /// through a `$default` stub with a **non-zero mask** is NOT optimized
    /// into a loop.  Because we cannot inline default expressions at the
    /// lowering stage, the `$default` stub call must be preserved so that
    /// the default values are correctly evaluated on each recursive call.
    func testTailrecPreservesDefaultStubCallWithNonZeroMask() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let fnSymbol = SymbolID(rawValue: 400)
        let defaultStubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: fnSymbol)
        let paramN = SymbolID(rawValue: 401)
        let paramAcc = SymbolID(rawValue: 402)

        let intType = types.make(.primitive(.int, .nonNull))
        let nExpr = arena.appendExpr(.symbolRef(paramN))
        let accExpr = arena.appendExpr(.symbolRef(paramAcc))
        let zeroExpr = arena.appendExpr(.intLiteral(0))
        let oneExpr = arena.appendExpr(.intLiteral(1))
        let subResult = arena.appendExpr(.temporary(0))
        // Sentinel value for the defaulted second parameter
        let sentinelExpr = arena.appendExpr(.intLiteral(0))
        // Default mask: bit 1 set means param index 1 uses default
        let maskExpr = arena.appendExpr(.intLiteral(2))
        let callResult = arena.appendExpr(.temporary(1))

        let tailrecFunction = KIRFunction(
            symbol: fnSymbol,
            name: interner.intern("countdown"),
            params: [KIRParameter(symbol: paramN, type: intType), KIRParameter(symbol: paramAcc, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: nExpr, value: .symbolRef(paramN)),
                .constValue(result: accExpr, value: .symbolRef(paramAcc)),
                // if (n == 0) jump to base case
                .jumpIfEqual(lhs: nExpr, rhs: zeroExpr, target: 1),
                // recursive case: countdown$default(n - 1, 0_sentinel, mask=2)
                .binary(op: .subtract, lhs: nExpr, rhs: oneExpr, result: subResult),
                .constValue(result: sentinelExpr, value: .intLiteral(0)),
                .constValue(result: maskExpr, value: .intLiteral(2)),
                .call(
                    symbol: defaultStubSymbol,
                    callee: interner.intern("countdown$default"),
                    arguments: [subResult, sentinelExpr, maskExpr],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
                // base case
                .label(1),
                .returnValue(accExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false,
            isTailrec: true
        )

        let lowered = try runTailrecPass(
            function: tailrecFunction, arena: arena,
            moduleName: "TailrecDefaultStub", interner: interner
        )

        // The $default stub call should be PRESERVED (not optimized)
        // because the non-zero mask means some params use defaults and
        // we cannot inline their default expressions at this stage.
        let hasDefaultStubCall = lowered.body.contains { instruction in
            if case let .call(sym, _, _, _, _, _, _, _) = instruction, sym == defaultStubSymbol {
                return true
            }
            return false
        }
        XCTAssertTrue(hasDefaultStubCall, "$default stub call with non-zero mask should be preserved (cannot inline default expressions)")

        // No tailrec loop should have been created for this call.
        let hasJumpToLoop = lowered.body.contains { instruction in
            if case let .jump(target) = instruction {
                return target >= tailrecLoopLabelBase
            }
            return false
        }
        XCTAssertFalse(hasJumpToLoop, "No tailrec loop jump expected when $default mask is non-zero")
    }

    /// LOWER-005: Verify that a `$default` stub call with mask=0 (all
    /// arguments explicitly provided) IS optimized into a loop.
    func testTailrecRewritesDefaultStubCallWithZeroMask() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let fnSymbol = SymbolID(rawValue: 450)
        let defaultStubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: fnSymbol)
        let paramN = SymbolID(rawValue: 451)
        let paramAcc = SymbolID(rawValue: 452)

        let intType = types.make(.primitive(.int, .nonNull))
        let nExpr = arena.appendExpr(.symbolRef(paramN))
        let accExpr = arena.appendExpr(.symbolRef(paramAcc))
        let zeroExpr = arena.appendExpr(.intLiteral(0))
        let oneExpr = arena.appendExpr(.intLiteral(1))
        let subResult = arena.appendExpr(.temporary(0))
        let mulResult = arena.appendExpr(.temporary(1))
        // mask=0: all arguments explicitly provided
        let maskExpr = arena.appendExpr(.intLiteral(0))
        let callResult = arena.appendExpr(.temporary(2))

        let tailrecFunction = KIRFunction(
            symbol: fnSymbol,
            name: interner.intern("fact"),
            params: [KIRParameter(symbol: paramN, type: intType), KIRParameter(symbol: paramAcc, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: nExpr, value: .symbolRef(paramN)),
                .constValue(result: accExpr, value: .symbolRef(paramAcc)),
                // if (n == 0) jump to base case
                .jumpIfEqual(lhs: nExpr, rhs: zeroExpr, target: 1),
                // recursive case: fact$default(n - 1, n * acc, mask=0)
                .binary(op: .subtract, lhs: nExpr, rhs: oneExpr, result: subResult),
                .binary(op: .multiply, lhs: nExpr, rhs: accExpr, result: mulResult),
                .constValue(result: maskExpr, value: .intLiteral(0)),
                .call(
                    symbol: defaultStubSymbol,
                    callee: interner.intern("fact$default"),
                    arguments: [subResult, mulResult, maskExpr],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
                // base case
                .label(1),
                .returnValue(accExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false,
            isTailrec: true
        )

        let lowered = try runTailrecPass(
            function: tailrecFunction, arena: arena,
            moduleName: "TailrecDefaultZeroMask", interner: interner
        )

        // The $default stub call should be eliminated (mask=0 is safe).
        let hasDefaultStubCall = lowered.body.contains { instruction in
            if case let .call(sym, _, _, _, _, _, _, _) = instruction, sym == defaultStubSymbol {
                return true
            }
            return false
        }
        XCTAssertFalse(hasDefaultStubCall, "$default stub call with mask=0 should be eliminated by tailrec lowering")

        // The loop-head label should be present.
        let hasLoopLabel = lowered.body.contains { instruction in
            if case let .label(id) = instruction {
                return id >= tailrecLoopLabelBase
            }
            return false
        }
        XCTAssertTrue(hasLoopLabel, "Expected loop-head label for mask=0 $default call")

        // The jump back to loop head should be present.
        let hasJumpBack = lowered.body.contains { instruction in
            if case let .jump(target) = instruction {
                return target >= tailrecLoopLabelBase
            }
            return false
        }
        XCTAssertTrue(hasJumpBack, "Expected jump back to loop head for mask=0 $default call")
    }

    /// LOWER-005: Verify that the slow-path in `extractDefaultMask` correctly
    /// resolves the mask via a preceding `.constValue` instruction (not an
    /// inline `.intLiteral` arena expression).  With a non-zero mask, the
    /// call should be preserved (not optimized) because we cannot inline
    /// default expressions at the lowering stage.
    func testTailrecPreservesDefaultStubCallWithTemporaryNonZeroMask() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let fnSymbol = SymbolID(rawValue: 500)
        let defaultStubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: fnSymbol)
        let paramN = SymbolID(rawValue: 501)
        let paramAcc = SymbolID(rawValue: 502)

        let intType = types.make(.primitive(.int, .nonNull))
        let nExpr = arena.appendExpr(.symbolRef(paramN))
        let accExpr = arena.appendExpr(.symbolRef(paramAcc))
        let zeroExpr = arena.appendExpr(.intLiteral(0))
        let oneExpr = arena.appendExpr(.intLiteral(1))
        let subResult = arena.appendExpr(.temporary(0))
        // Sentinel value for the defaulted second parameter
        let sentinelExpr = arena.appendExpr(.intLiteral(0))
        // Use a .temporary expression for the mask -- NOT an inline .intLiteral
        // -- so the fast path in extractDefaultMask misses and the slow path
        // (backward scan for preceding constValue) is exercised.
        let maskTemp = arena.appendExpr(.temporary(99))
        let callResult = arena.appendExpr(.temporary(1))

        let tailrecFunction = KIRFunction(
            symbol: fnSymbol,
            name: interner.intern("countdown"),
            params: [KIRParameter(symbol: paramN, type: intType), KIRParameter(symbol: paramAcc, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: nExpr, value: .symbolRef(paramN)),
                .constValue(result: accExpr, value: .symbolRef(paramAcc)),
                // if (n == 0) jump to base case
                .jumpIfEqual(lhs: nExpr, rhs: zeroExpr, target: 1),
                // recursive case: countdown$default(n - 1, 0_sentinel, mask_temp)
                .binary(op: .subtract, lhs: nExpr, rhs: oneExpr, result: subResult),
                .constValue(result: sentinelExpr, value: .intLiteral(0)),
                // The mask is defined via constValue into a temporary -- this
                // exercises the slow-path backward scan in extractDefaultMask.
                .constValue(result: maskTemp, value: .intLiteral(2)),
                .call(
                    symbol: defaultStubSymbol,
                    callee: interner.intern("countdown$default"),
                    arguments: [subResult, sentinelExpr, maskTemp],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
                // base case
                .label(1),
                .returnValue(accExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false,
            isTailrec: true
        )

        let lowered = try runTailrecPass(
            function: tailrecFunction, arena: arena,
            moduleName: "TailrecSlowPathMask", interner: interner
        )

        // The $default stub call should be PRESERVED because the mask is
        // non-zero (slow-path resolved mask=2).
        let hasDefaultStubCall = lowered.body.contains { instruction in
            if case let .call(sym, _, _, _, _, _, _, _) = instruction, sym == defaultStubSymbol {
                return true
            }
            return false
        }
        XCTAssertTrue(hasDefaultStubCall, "$default stub call with non-zero mask should be preserved (slow-path mask test)")

        // No tailrec loop should have been created for this call.
        let hasJumpToLoop = lowered.body.contains { instruction in
            if case let .jump(target) = instruction {
                return target >= tailrecLoopLabelBase
            }
            return false
        }
        XCTAssertFalse(hasJumpToLoop, "No tailrec loop jump expected when $default mask is non-zero (slow-path mask test)")
    }

    /// LOWER-005: Verify that the slow-path in `extractDefaultMask` correctly
    /// resolves a mask=0 via a preceding `.constValue` instruction and the
    /// call IS optimized into a loop (since mask=0 means all args provided).
    func testTailrecRewritesDefaultStubCallWithTemporaryZeroMask() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let fnSymbol = SymbolID(rawValue: 550)
        let defaultStubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: fnSymbol)
        let paramN = SymbolID(rawValue: 551)
        let paramAcc = SymbolID(rawValue: 552)

        let intType = types.make(.primitive(.int, .nonNull))
        let nExpr = arena.appendExpr(.symbolRef(paramN))
        let accExpr = arena.appendExpr(.symbolRef(paramAcc))
        let zeroExpr = arena.appendExpr(.intLiteral(0))
        let oneExpr = arena.appendExpr(.intLiteral(1))
        let subResult = arena.appendExpr(.temporary(0))
        let mulResult = arena.appendExpr(.temporary(1))
        // Use a .temporary expression for the mask (value 0) -- exercises
        // the slow-path backward scan in extractDefaultMask.
        let maskTemp = arena.appendExpr(.temporary(99))
        let callResult = arena.appendExpr(.temporary(2))

        let tailrecFunction = KIRFunction(
            symbol: fnSymbol,
            name: interner.intern("fact"),
            params: [KIRParameter(symbol: paramN, type: intType), KIRParameter(symbol: paramAcc, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: nExpr, value: .symbolRef(paramN)),
                .constValue(result: accExpr, value: .symbolRef(paramAcc)),
                // if (n == 0) jump to base case
                .jumpIfEqual(lhs: nExpr, rhs: zeroExpr, target: 1),
                // recursive case: fact$default(n - 1, n * acc, mask_temp=0)
                .binary(op: .subtract, lhs: nExpr, rhs: oneExpr, result: subResult),
                .binary(op: .multiply, lhs: nExpr, rhs: accExpr, result: mulResult),
                // The mask is defined via constValue into a temporary
                .constValue(result: maskTemp, value: .intLiteral(0)),
                .call(
                    symbol: defaultStubSymbol,
                    callee: interner.intern("fact$default"),
                    arguments: [subResult, mulResult, maskTemp],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
                // base case
                .label(1),
                .returnValue(accExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false,
            isTailrec: true
        )

        let lowered = try runTailrecPass(
            function: tailrecFunction, arena: arena,
            moduleName: "TailrecSlowPathZeroMask", interner: interner
        )

        // The $default stub call should be eliminated (mask=0 via slow path).
        let hasDefaultStubCall = lowered.body.contains { instruction in
            if case let .call(sym, _, _, _, _, _, _, _) = instruction, sym == defaultStubSymbol {
                return true
            }
            return false
        }
        XCTAssertFalse(hasDefaultStubCall, "$default stub call with mask=0 should be eliminated (slow-path mask test)")

        // The loop-head label and jump should be present.
        let hasLoopLabel = lowered.body.contains { instruction in
            if case let .label(id) = instruction { return id >= tailrecLoopLabelBase }
            return false
        }
        XCTAssertTrue(hasLoopLabel, "Expected loop-head label (slow-path zero-mask test)")

        let hasJumpBack = lowered.body.contains { instruction in
            if case let .jump(target) = instruction { return target >= tailrecLoopLabelBase }
            return false
        }
        XCTAssertTrue(hasJumpBack, "Expected jump back to loop head (slow-path zero-mask test)")
    }

    // MARK: - Sema warning test

    /// Verify that KSWIFTK-SEMA-TAILREC warning is emitted when the last
    /// expression is not a self-recursive call.
    func testSemaTailrecWarningOnNonRecursiveBody() throws {
        let source = """
        tailrec fun notRecursive(n: Int): Int {
            return n + 1
        }
        fun main() = notRecursive(5)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SemaTailrecWarn")
            try runSema(ctx)

            let hasTailrecWarning = ctx.diagnostics.diagnostics.contains { diag in
                diag.code == "KSWIFTK-SEMA-TAILREC" && diag.severity == .warning
            }
            XCTAssertTrue(hasTailrecWarning, "Expected KSWIFTK-SEMA-TAILREC warning for non-recursive tailrec function")
        }
    }

    // MARK: - E2E integration test

    /// Compile a tailrec factorial function and verify that tailrec lowering
    /// transforms the recursion into a loop in KIR (no self-recursive calls
    /// remain and control flow uses a loop-head label with jump).
    func testTailrecFactorialLoweredToLoop() throws {
        let source = """
        tailrec fun fact(n: Int, acc: Int = 1): Int {
            if (n == 0) return acc
            return fact(n - 1, n * acc)
        }
        fun main(): Int = fact(100000)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "TailrecE2E", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)

            // Find the fact function and verify it was optimized.
            let factFunction = try findKIRFunction(
                named: "fact", in: module, interner: ctx.interner
            )

            // The function should have the tailrec flag.
            XCTAssertTrue(factFunction.isTailrec)

            // Should have a loop-head label.
            let hasLoopLabel = factFunction.body.contains { instruction in
                if case let .label(id) = instruction {
                    return id >= tailrecLoopLabelBase
                }
                return false
            }
            XCTAssertTrue(hasLoopLabel, "Expected loop-head label in tailrec function")

            // Should have a jump back to the loop head.
            let hasJumpBack = factFunction.body.contains { instruction in
                if case let .jump(target) = instruction {
                    return target >= tailrecLoopLabelBase
                }
                return false
            }
            XCTAssertTrue(hasJumpBack, "Expected jump back to loop head in tailrec function")

            // Self-recursive calls to 'fact' should have been eliminated.
            let factName = ctx.interner.intern("fact")
            let hasSelfCall = factFunction.body.contains { instruction in
                if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                    return callee == factName
                }
                return false
            }
            XCTAssertFalse(hasSelfCall, "Self-recursive call should have been eliminated by tailrec lowering")

            // No errors in diagnostics.
            XCTAssertFalse(ctx.diagnostics.hasError, "Compilation should succeed without errors")
        }
    }
}
