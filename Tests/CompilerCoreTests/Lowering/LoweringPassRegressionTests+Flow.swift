@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
    func testCoroutineLoweringRewritesFlowMemberChainToRuntimeABI() throws {
        let source = """
        fun main() {
            val stream = flow {
                emit(1)
                emit(2)
            }
            stream.map { it }.filter { true }.take(1).collect { println(it) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowMemberLowering", emit: .kirDump)
            try runToKIR(ctx)

            let errorCodesBeforeLowering = ctx.diagnostics.diagnostics
                .filter { $0.severity == .error }
                .map(\.code)
            XCTAssertTrue(
                errorCodesBeforeLowering.isEmpty,
                "Unexpected diagnostics before lowering: \(errorCodesBeforeLowering)"
            )

            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let allFunctionBodies: [[KIRInstruction]] = module.arena.declarations.compactMap { decl in
                guard case let .function(function) = decl else {
                    return nil
                }
                return function.body
            }
            let allCallNames = allFunctionBodies.flatMap { extractCallees(from: $0, interner: ctx.interner) }

            XCTAssertTrue(allCallNames.contains("kk_flow_create"))
            XCTAssertTrue(allCallNames.contains("kk_flow_emit"))
            XCTAssertTrue(allCallNames.contains("kk_flow_map"))
            XCTAssertTrue(allCallNames.contains("kk_flow_filter"))
            XCTAssertTrue(allCallNames.contains("kk_flow_take"))
            XCTAssertTrue(allCallNames.contains("kk_flow_collect"))

            XCTAssertFalse(allCallNames.contains("flow"))
            XCTAssertFalse(allCallNames.contains("emit"))
            XCTAssertFalse(allCallNames.contains("map"))
            XCTAssertFalse(allCallNames.contains("filter"))
            XCTAssertFalse(allCallNames.contains("take"))
            XCTAssertFalse(allCallNames.contains("collect"))
        }
    }

    func testCoroutineLoweringPreservesThrowMetadataWhenRewritingVirtualCollect() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let functionSymbol = SymbolID(rawValue: 4600)

        let flowLambda = arena.appendExpr(.temporary(0), type: types.anyType)
        let flowHandle = arena.appendExpr(.temporary(1), type: types.anyType)
        let collectorLambda = arena.appendExpr(.temporary(2), type: types.anyType)
        let collectResult = arena.appendExpr(.temporary(3), type: types.unitType)
        let thrownSlot = arena.appendExpr(.temporary(4), type: types.anyType)

        let function = KIRFunction(
            symbol: functionSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("flow"),
                    arguments: [flowLambda],
                    result: flowHandle,
                    canThrow: false,
                    thrownResult: nil
                ),
                .virtualCall(
                    symbol: nil,
                    callee: interner.intern("collect"),
                    receiver: flowHandle,
                    arguments: [collectorLambda],
                    result: collectResult,
                    canThrow: true,
                    thrownResult: thrownSlot,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "FlowVirtualCollectThrow",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module

        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: interner,
            sema: ctx.sema
        )
        try CoroutineLoweringPass().run(module: module, ctx: kirCtx)

        guard case let .function(lowered)? = module.arena.decl(functionID) else {
            XCTFail("expected lowered function")
            return
        }

        let rewrittenCollectCalls: [(canThrow: Bool, thrownResult: KIRExprID?)] = lowered.body.compactMap { instruction in
            guard case let .call(_, callee, _, _, canThrow, thrownResult, _) = instruction,
                  interner.resolve(callee) == "kk_flow_collect"
            else {
                return nil
            }
            return (canThrow: canThrow, thrownResult: thrownResult)
        }

        XCTAssertEqual(rewrittenCollectCalls.count, 1, "Expected exactly one rewritten kk_flow_collect call.")
        XCTAssertEqual(rewrittenCollectCalls[0].canThrow, true)
        XCTAssertEqual(rewrittenCollectCalls[0].thrownResult, thrownSlot)
    }
}
