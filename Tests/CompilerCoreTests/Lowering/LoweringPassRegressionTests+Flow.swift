@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
    func testFlowLoweringRewritesFlowCallsToRuntimeABI() throws {
        let source = """
        fun main() {
            runBlocking {
                flow {
                    emit(1)
                    emit(2)
                }.map { it * 2 }
                    .collect { println(it) }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowLoweringRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            var allCallees: [String] = []
            for decl in module.arena.declarations {
                guard case let .function(function) = decl else {
                    continue
                }
                allCallees.append(contentsOf: extractCallees(from: function.body, interner: ctx.interner))
            }

            XCTAssertTrue(allCallees.contains("kk_flow_create"))
            XCTAssertTrue(allCallees.contains("kk_flow_emit"))
            XCTAssertTrue(allCallees.contains("kk_flow_collect"))
            XCTAssertFalse(allCallees.contains("flow"))
            XCTAssertFalse(allCallees.contains("map"))
            XCTAssertFalse(allCallees.contains("collect"))
            XCTAssertFalse(allCallees.contains("emit"))
        }
    }

    func testCoroutineLoweringFlowCollectInjectsSuspendCollectorFunctionID() throws {
        let source = """
        fun main() {
            runBlocking {
                flow {
                    emit(1)
                }.collect {
                    delay(1)
                    println(it)
                }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowCollectSuspend", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            var collectCallArgs: [KIRExprID]?
            for decl in module.arena.declarations {
                guard case let .function(function) = decl else {
                    continue
                }
                for instruction in function.body {
                    guard case let .call(_, callee, arguments, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_flow_collect"
                    else {
                        continue
                    }
                    collectCallArgs = arguments
                    break
                }
                if collectCallArgs != nil {
                    break
                }
            }

            let callArgs = try XCTUnwrap(collectCallArgs, "Expected kk_flow_collect call after lowering.")
            XCTAssertEqual(callArgs.count, 3)

            guard let collectorExpr = module.arena.expr(callArgs[1]),
                  case let .symbolRef(collectorSymbol) = collectorExpr
            else {
                XCTFail("kk_flow_collect collector argument must be a symbol reference.")
                return
            }

            let collectorFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return function.symbol == collectorSymbol ? function : nil
            }.first
            let collectorName = collectorFunction.map { ctx.interner.resolve($0.name) } ?? ""
            XCTAssertTrue(
                collectorName.hasPrefix("kk_suspend_"),
                "Collector argument should be rewritten to suspend-lowered entry point."
            )

            guard let functionIDExpr = module.arena.expr(callArgs[2]),
                  case let .intLiteral(functionID) = functionIDExpr
            else {
                XCTFail("kk_flow_collect third argument must be a function ID literal.")
                return
            }
            XCTAssertNotEqual(functionID, 0)
            XCTAssertEqual(functionID, Int64(collectorSymbol.rawValue))
        }
    }

    func testFlowMapCollectExecutablePrintsExpectedOutput() throws {
        let source = """
        suspend fun runFlowCollectExecutable() {
            flow {
                emit(1)
                emit(2)
            }.map { it * 2 }
                .collect { println(it) }
        }

        fun main() {
            runBlocking(::runFlowCollectExecutable)
            return
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "FlowExecutable",
            expectedStdout: "2\n4\n"
        )
    }

    func testFlowCollectTwiceReexecutesEmitterForColdSemantics() throws {
        let source = """
        suspend fun runFlowCollectTwice() {
            val stream = flow {
                emit(1)
                emit(2)
            }.map { it * 2 }
            stream.collect { println(it) }
            stream.collect { println(it) }
        }

        fun main() {
            runBlocking(::runFlowCollectTwice)
            return
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "FlowColdExecutable",
            expectedStdout: "2\n4\n2\n4\n"
        )
    }

    func testFlowLoweringInsertsFlowHandleReleaseCalls() throws {
        let source = """
        suspend fun runFlowOwnership() {
            val stream = flow {
                emit(1)
                emit(2)
            }
            val mapped = stream.map { it }
            stream.collect { println(it) }
            mapped.collect { println(it) }
        }

        fun main() {
            runBlocking(::runFlowOwnership)
            return
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowOwnership", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            var allCallees: [String] = []
            for decl in module.arena.declarations {
                guard case let .function(function) = decl else {
                    continue
                }
                allCallees.append(contentsOf: extractCallees(from: function.body, interner: ctx.interner))
            }

            XCTAssertTrue(allCallees.contains("kk_flow_release"))
        }
    }

    private func assertFlowExecutableOutput(
        source: String,
        moduleName: String,
        expectedStdout: String,
        irFlags: [String] = []
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputPath,
                irFlags: irFlags
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let runResult = try CommandRunner.run(executable: outputPath, arguments: [])
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(runResult.exitCode, 0)
            XCTAssertEqual(normalizedStdout, expectedStdout)
        }
    }
}
