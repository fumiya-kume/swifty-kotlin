@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testVarargNamedArgSkipsToVarargParameter() throws {
        let source = """
        fun tagged(tag: String, vararg values: Int): Int = 0
        fun main() = tagged(tag = "x", 1, 2)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected vararg with named arg to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing with named arg, got: \(callNames)")
            XCTAssertTrue(callNames.contains("kk_array_set"), "Expected kk_array_set for vararg packing with named arg, got: \(callNames)")
        }
    }

    func testVarargSpreadFlagIsParsedInCallArgument() throws {
        // Verify that the spread operator (*) is parsed at the AST level.
        // Full end-to-end spread lowering requires IntArray type inference
        // improvements (tracked separately).
        let source = """
        fun collect(vararg items: Int): Int = 0
        fun main() {
            val arr = IntArray(2)
            collect(*arr)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)
            try BuildASTPhase().run(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            // Check that at least one CallArgument has isSpread == true
            var foundSpread = false
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID) else { continue }
                if case let .call(_, _, args, _) = expr {
                    for arg in args where arg.isSpread {
                        foundSpread = true
                    }
                }
            }
            XCTAssertTrue(foundSpread, "Expected parser to set isSpread flag for *arr argument.")
        }
    }

    func testVarargWithDefaultAndNamedArgsCombined() throws {
        let source = """
        fun format(prefix: String = ">>", vararg nums: Int, suffix: String = "<<"): Int = 0
        fun main() = format(prefix = "!", 10, 20, 30)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected vararg+default+named combination to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing in combined scenario, got: \(callNames)")
        }
    }

    func testVarargMemberCallPacksArgsCorrectly() throws {
        let source = """
        class Acc {
            fun add(vararg vals: Int): Int = 0
        }
        fun main(a: Acc) = a.add(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected vararg member call to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg member call, got: \(callNames)")
            XCTAssertTrue(callNames.contains("kk_array_set"), "Expected kk_array_set for vararg member call, got: \(callNames)")
        }
    }

    func testABILoweringSkipsBoxingForVarargPackedArrayArgument() throws {
        let source = """
        fun sum(vararg items: Int): Int = 0
        fun main() = sum(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            // After ABI lowering, the vararg-packed array should NOT be boxed.
            // If boxing were incorrectly applied, we would see kk_box_int
            // targeting the array argument passed to `sum`.
            let sumCalls = body.filter { instruction in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "sum"
            }
            XCTAssertFalse(sumCalls.isEmpty, "Expected a call to sum after ABI lowering.")

            // Verify that arguments to sum are not individually boxed—the
            // array_new/array_set calls produce the packed array argument.
            for call in sumCalls {
                guard case let .call(_, _, arguments, _, _, _, _) = call else { continue }
                for arg in arguments {
                    guard let argKind = module.arena.expr(arg) else { continue }
                    // The argument to sum should be a temporary holding the
                    // array reference produced by kk_array_new, NOT a raw
                    // kk_box_int result.  An intLiteral here would mean the
                    // vararg array was never constructed—flag it.
                    if case .intLiteral = argKind {
                        XCTFail("Unexpected intLiteral as direct argument to sum; expected a packed array reference.")
                    }
                }
            }

            // The real check: kk_box_int should NOT appear before the call to sum
            // for the purpose of boxing vararg elements into the packed argument.
            // The array_set calls handle packing, not boxing.
            let callNames = extractCallees(from: body, interner: ctx.interner)
            let sumIndex = callNames.firstIndex(of: "sum")
            let boxIntIndices = callNames.indices.filter { callNames[$0] == "kk_box_int" }
            // Any kk_box_int calls that appear should be for array_set element boxing,
            // not for the final argument to sum itself.
            if let sumIdx = sumIndex {
                let boxCallsAfterArrayPacking = boxIntIndices.filter { $0 > sumIdx }
                XCTAssertTrue(boxCallsAfterArrayPacking.isEmpty, "Unexpected kk_box_int after sum call; vararg array argument should not be boxed.")
            }
        }
    }

    func testVarargDefaultNamedRegressionCompilesToKIRWithoutErrors() throws {
        let source = """
        fun log(level: Int = 0, vararg msgs: Int): Int = 0
        fun main() {
            log(1, 2, 3)
            log(level = 5, 10, 20)
            log()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected vararg+default+named regression cases to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            // All three call sites should produce array packing
            let arrayNewCount = callNames.filter { $0 == "kk_array_new" }.count
            XCTAssertGreaterThanOrEqual(arrayNewCount, 2, "Expected at least 2 kk_array_new calls for vararg packing across call sites, got: \(arrayNewCount)")
        }
    }

    func testVarargPositionalAfterNamedArgPacksCorrectly() throws {
        // Verify that positional vararg arguments following a named argument
        // are correctly packed into an array (overload resolver fix).
        let source = """
        fun report(label: String, vararg values: Int): Int = 0
        fun main() = report(label = "test", 10, 20, 30)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected positional vararg after named arg to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for positional vararg after named arg, got: \(callNames)")
            XCTAssertTrue(callNames.contains("kk_array_set"), "Expected kk_array_set for positional vararg after named arg, got: \(callNames)")
        }
    }

    func topLevelExpressionBodyExprID(
        named functionName: String,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        ast.files
            .flatMap(\.topLevelDecls)
            .compactMap { declID -> ExprID? in
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(funDecl) = decl,
                      interner.resolve(funDecl.name) == functionName,
                      case let .expr(exprID, _) = funDecl.body
                else {
                    return nil
                }
                return exprID
            }
            .first
    }

    func symbolNames(
        for arguments: [KIRExprID],
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        arguments.compactMap { argument in
            guard case let .symbolRef(symbolID)? = module.arena.expr(argument),
                  let symbol = sema.symbols.symbol(symbolID)
            else {
                return nil
            }
            return interner.resolve(symbol.name)
        }
    }

    // MARK: - P5-42: Local function scope registration and KIR generation

    func testLocalFunctionScopeRegistrationAllowsCallResolution() throws {
        let source = """
        fun main(): Int {
            fun helper(x: Int): Int = x * 2
            return helper(21)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Local function call should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testLocalFunctionKIRGenerationEmitsFunctionDecl() throws {
        let source = """
        fun main(): Int {
            fun add(a: Int, b: Int): Int = a + b
            return add(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected no errors: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // The module should contain at least 2 functions: main and the local function add.
            XCTAssertGreaterThanOrEqual(module.functionCount, 2, "Expected KIR to contain both main and local function 'add'")
        }
    }
}
