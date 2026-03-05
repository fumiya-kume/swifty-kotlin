@testable import CompilerCore
import Foundation
import XCTest

final class TailrecLoweringTests: XCTestCase {
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

        let fnID = arena.appendDecl(.function(tailrecFunction))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])],
            arena: arena
        )

        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "TailrecTest",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        try TailrecLoweringPass().run(module: module, ctx: ctx)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected lowered function")
            return
        }

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
            if case let .call(sym, _, _, _, _, _, _) = instruction, sym == fnSymbol {
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

        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "NonTailrecTest",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        // shouldRun should return false.
        XCTAssertFalse(TailrecLoweringPass().shouldRun(module: module, ctx: ctx))
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
                if case let .call(_, callee, _, _, _, _, _) = instruction {
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
