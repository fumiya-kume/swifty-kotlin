@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testThisBasedMemberCallCompilesAndUsesImplicitReceiverInLowering() throws {
        let source = """
        class Vec
        fun Vec.plus(other: Vec): Vec = this
        fun Vec.combine(other: Vec): Vec = this.plus(other)
        fun useCombine(a: Vec, b: Vec): Vec = a.combine(b)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected this-based member call program to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let combineFunction = try findKIRFunction(named: "combine", in: module, interner: ctx.interner)
            let plusCall = try XCTUnwrap(combineFunction.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "plus"
            })
            guard case let .call(_, _, arguments, _, _, _, _) = plusCall else {
                XCTFail("Expected combine to lower to a call to plus.")
                return
            }

            let implicitReceiverSymbol = try XCTUnwrap(combineFunction.params.first?.symbol)
            XCTAssertEqual(arguments.count, 2)
            guard case let .symbolRef(insertedReceiver)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected first argument to be a symbolRef for implicit this receiver.")
                return
            }
            XCTAssertEqual(insertedReceiver, implicitReceiverSymbol)
        }
    }

    func testABILoweringInsertsBoxingCallsForPrimitiveToAnyBoundary() throws {
        let source = """
        fun acceptAny(x: Any?) = x
        fun main() {
            acceptAny(42)
            acceptAny(true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_box_int"))
            XCTAssertTrue(callNames.contains("kk_box_bool"))
        }
    }

    func testABILoweringBoxingCallsAreNonThrowing() throws {
        let source = """
        fun acceptAny(x: Any?) = x
        fun main() {
            acceptAny(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let boxingThrowFlags = body.compactMap { instruction -> Bool? in
                guard case let .call(_, callee, _, _, canThrow, _, _) = instruction else {
                    return nil
                }
                let name = ctx.interner.resolve(callee)
                guard name == "kk_box_int" || name == "kk_box_bool" ||
                    name == "kk_unbox_int" || name == "kk_unbox_bool"
                else {
                    return nil
                }
                return canThrow
            }
            XCTAssertFalse(boxingThrowFlags.isEmpty)
            XCTAssertTrue(boxingThrowFlags.allSatisfy { $0 == false })
        }
    }

    func testStringStdlibThrowFlagsAreClassifiedByABI() throws {
        let source = """
        fun main() {
            "  hi  ".trim()
            "1,2,3".split(",")
            "42".toInt()
            "3.14".toDouble()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            XCTAssertEqual(throwFlags["kk_string_trim"]?.allSatisfy { $0 == false }, true)
            XCTAssertEqual(throwFlags["kk_string_split"]?.allSatisfy { $0 == true }, true)
            XCTAssertEqual(throwFlags["kk_string_toInt"]?.allSatisfy { $0 == true }, true)
            XCTAssertEqual(throwFlags["kk_string_toDouble"]?.allSatisfy { $0 == true }, true)
        }
    }

    func testArrayAccessAndAssignmentLowerToRuntimeCallsWithExpectedThrowFlags() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(2)
            arr[0] = 7
            return arr[0]
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_array_new"))
            XCTAssertTrue(callNames.contains("kk_array_set"))
            XCTAssertTrue(callNames.contains("kk_array_get"))

            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            XCTAssertEqual(throwFlags["kk_array_new"]?.allSatisfy { $0 == false }, true)
            XCTAssertEqual(throwFlags["kk_array_set"]?.allSatisfy { $0 == true }, true)
            XCTAssertEqual(throwFlags["kk_array_get"]?.allSatisfy { $0 == true }, true)
        }
    }

    func testArrayOutOfBoundsThrownChannelReturnsEarlyBeforeSubsequentReturn() throws {
        let source = """
        fun readOutOfBounds(arr: Any?): Any? = arr[5]
        fun main(): Any? {
            val arr = IntArray(1)
            readOutOfBounds(arr)
            return 99
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ArrayThrownChannel",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected top-level thrown channel to fail process exit.")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                result = failed
            } catch {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.stderr.contains("KSWIFTK-LINK-0003"))
        }
    }

    func testFrontendAndSemaResolveTypedDeclarationsAndEmitExpectedDiagnostics() throws {
        let source = """
        package typed.demo
        import typed.demo.*

        public inline suspend fun transform<T>(
            vararg values: T,
            crossinline mapper: T,
            noinline fallback: T = mapper
        ): String? = "ok"
        fun String.decorate(): String = this

        fun typed(a: Int, b: String?, c: Any): Int = 1
        fun duplicate(x: Int, x: Int): Int = x

        val explicit: Int = 1
        var delegated by delegateProvider
        val unknown: CustomType = explicit
        val explicit: Int = 2

        class TypedBox<T>(value: T)
        object Obj
        typealias Alias = String
        enum class Kind { A, B }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "Typed", emit: .kirDump)
            try runToKIR(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let declarations = ast.arena.declarations()
            XCTAssertGreaterThanOrEqual(declarations.count, 8)

            var sawTypedParameter = false
            var sawFunctionReturnType = false
            var sawFunctionReceiverType = false
            var sawExplicitPropertyType = false
            var sawDelegatedPropertyWithoutType = false

            for decl in declarations {
                switch decl {
                case let .funDecl(fn):
                    if fn.returnType != nil {
                        sawFunctionReturnType = true
                    }
                    if fn.receiverType != nil {
                        sawFunctionReceiverType = true
                    }
                    if fn.valueParams.contains(where: { $0.type != nil }) {
                        sawTypedParameter = true
                    }
                case let .propertyDecl(property):
                    if let typeID = property.type, let typeRef = ast.arena.typeRef(typeID) {
                        sawExplicitPropertyType = true
                        if case let .named(path, _, _) = typeRef {
                            XCTAssertFalse(path.isEmpty)
                        }
                    } else if ctx.interner.resolve(property.name) == "delegated" {
                        sawDelegatedPropertyWithoutType = true
                    }
                default:
                    continue
                }
            }

            XCTAssertTrue(sawTypedParameter)
            XCTAssertTrue(sawFunctionReturnType)
            XCTAssertTrue(sawFunctionReceiverType)
            XCTAssertTrue(sawExplicitPropertyType)
            XCTAssertTrue(sawDelegatedPropertyWithoutType)

            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.symbols.allSymbols().isEmpty)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
            let decorateSymbol = sema.symbols.allSymbols().first(where: { symbol in
                ctx.interner.resolve(symbol.name) == "decorate"
            })
            XCTAssertNotNil(decorateSymbol)
            if let decorateSymbol {
                let signature = sema.symbols.functionSignature(for: decorateSymbol.id)
                XCTAssertNotNil(signature?.receiverType)
            }

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            XCTAssertTrue(codes.contains("KSWIFTK-TYPE-0002"))
            XCTAssertTrue(codes.contains("KSWIFTK-SEMA-0001"))
        }
    }
}
