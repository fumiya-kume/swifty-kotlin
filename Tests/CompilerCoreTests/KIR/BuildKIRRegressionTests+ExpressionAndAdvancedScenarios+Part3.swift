@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testExternalStringStubWithDefaultArgsDoesNotCallDefaultStub() throws {
        let source = """
        fun main() {
            val parts = "1,2,3".split(",")
            println(parts)
            println("abc".startsWith("a"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_string_split"), "Expected direct kk_string_split call, got: \(callees)")
            XCTAssertTrue(callees.contains("kk_string_startsWith"), "Expected direct kk_string_startsWith call, got: \(callees)")
            XCTAssertFalse(callees.contains { $0.contains("split$default") || $0.contains("startsWith$default") },
                           "External string stubs must not route through $default: \(callees)")
        }
    }

    func testDefaultArgNoStubWhenAllArgsProvided() throws {
        let source = """
        fun add(a: Int, b: Int = 10): Int = a + b
        fun main() = add(5, 20)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("add"), "Expected direct call to add, got: \(callees)")
            XCTAssertFalse(callees.contains("add$default"), "Should not call stub when all args provided, got: \(callees)")
        }
    }

    // MARK: - Default Argument Callee-Context Semantics (P5-56)

    func testDefaultArgStubBindsPrecedingParameterForDefaultExpression() throws {
        // Default expression `b = a + 1` must reference preceding parameter `a`
        // in callee context (the $default stub), not at the caller site.
        let source = """
        fun withDep(a: Int, b: Int = a + 1): Int = a + b
        fun main() = withDep(10)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            // Call site must route through $default stub
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            XCTAssertTrue(mainCallees.contains("withDep$default"),
                          "Expected call to withDep$default stub, got: \(mainCallees)")

            // Stub must exist and call the original function
            let stubFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "withDep$default" ? function : nil
            }.first
            XCTAssertNotNil(stubFunction, "Expected withDep$default stub function")
            if let stub = stubFunction {
                let stubCallees = extractCallees(from: stub.body, interner: ctx.interner)
                XCTAssertTrue(stubCallees.contains("withDep"),
                              "Stub should call original withDep, got: \(stubCallees)")
                // Stub body must contain a binary add for the default expression `a + 1`
                let hasBinaryAdd = stub.body.contains { instruction in
                    guard case let .binary(op, _, _, _) = instruction else { return false }
                    return op == .add
                }
                XCTAssertTrue(hasBinaryAdd,
                              "Stub should evaluate default `a + 1` with a binary add instruction")
            }
        }
    }

    func testDefaultArgStubEvaluatesMultipleDefaultsLeftToRightWithDependencies() throws {
        // fun chain(a: Int = 1, b: Int = a + 10, c: Int = b + 100): Int
        // When called with chain(), defaults should be evaluated left-to-right:
        //   a = 1, b = 1 + 10 = 11, c = 11 + 100 = 111
        // The stub must process parameters in order so that `b`'s default can
        // reference `a`'s resolved value, and `c`'s default can reference `b`'s.
        let source = """
        fun chain(a: Int = 1, b: Int = a + 10, c: Int = b + 100): Int = a + b + c
        fun main() = chain()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let stubFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "chain$default" ? function : nil
            }.first
            XCTAssertNotNil(stubFunction, "Expected chain$default stub function")
            if let stub = stubFunction {
                // The stub should have 3 original params + 1 mask param = 4 params
                XCTAssertEqual(stub.params.count, 4,
                               "Stub should have 3 original params + mask, got \(stub.params.count)")

                // Verify label pairs: each default param generates skip/after labels.
                // 3 defaults → 6 labels (2 per default), processed left-to-right.
                var labelOrder: [Int32] = []
                for instruction in stub.body {
                    if case let .label(id) = instruction {
                        labelOrder.append(id)
                    }
                }
                XCTAssertEqual(labelOrder.count, 6,
                               "Expected 6 labels (2 per default param), got \(labelOrder.count)")
                // Labels must be strictly ascending (left-to-right order).
                for i in 1 ..< labelOrder.count {
                    XCTAssertGreaterThan(labelOrder[i], labelOrder[i - 1],
                                         "Labels must be ascending for left-to-right evaluation")
                }
            }
        }
    }

    func testDefaultArgStubBindsReceiverForExtensionFunctionDefault() throws {
        // Extension function default referencing `this` must have the receiver
        // available in the $default stub's callee context.
        let source = """
        fun Int.addDefault(n: Int = this + 1): Int = this + n
        fun main() = 5.addDefault()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            // Call site must use the $default stub
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            XCTAssertTrue(mainCallees.contains("addDefault$default"),
                          "Expected call to addDefault$default stub, got: \(mainCallees)")

            // Stub must exist and include a receiver parameter
            let stubFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "addDefault$default" ? function : nil
            }.first
            XCTAssertNotNil(stubFunction, "Expected addDefault$default stub function")
            if let stub = stubFunction {
                // receiver + original param + mask = 3 params
                XCTAssertGreaterThanOrEqual(stub.params.count, 3,
                                            "Stub should have receiver + param + mask, got \(stub.params.count)")
                let stubCallees = extractCallees(from: stub.body, interner: ctx.interner)
                XCTAssertTrue(stubCallees.contains("addDefault"),
                              "Stub should call original addDefault, got: \(stubCallees)")
            }
        }
    }

    func testDefaultArgCallerDoesNotLowerDefaultExpressionDirectly() throws {
        // Verify the caller only emits a sentinel + mask and delegates to the
        // $default stub. The caller's instruction stream must NOT contain the
        // default expression's evaluation (no binary add for `a + 1`).
        let source = """
        fun compute(a: Int, b: Int = a + 1): Int = a + b
        fun main() = compute(5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            XCTAssertTrue(mainCallees.contains("compute$default"),
                          "Caller should route to compute$default, got: \(mainCallees)")

            // The caller (main) body should NOT have a binary add — that belongs
            // in the stub's callee-context evaluation.
            let callerHasBinaryAdd = mainBody.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else { return false }
                return op == .add
            }
            XCTAssertFalse(callerHasBinaryAdd,
                           "Caller must not directly evaluate the default expression (binary add)")
        }
    }

    // MARK: - Nested Return Propagation (P5-48)

    func testNestedReturnInsideIfBranchEmitsReturnValueInstruction() throws {
        let source = """
        fun choose(flag: Boolean): Int {
            if (flag) {
                return 1
            }
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "choose", in: module, interner: ctx.interner)
            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions (if-branch + fallthrough), got \(returnValues.count)")
        }
    }

    func testNestedReturnInsideBothIfElseBranchesEmitsReturnValues() throws {
        let source = """
        fun pick(flag: Boolean): Int {
            if (flag) {
                return 1
            } else {
                return 2
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)
            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions (then-branch + else-branch), got \(returnValues.count)")
        }
    }

    func testNestedReturnInsideWhenBranchEmitsReturnValueInstruction() throws {
        let source = """
        fun describe(x: Int): Int {
            return when (x) {
                1 -> return 10
                2 -> return 20
                else -> 0
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "describe", in: module, interner: ctx.interner)
            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions for when-branch returns, got \(returnValues.count)")
        }
    }

    func testNestedReturnInIfBranchDoesNotEmitDeadCopyInstruction() throws {
        let source = """
        fun choose(flag: Boolean): Int {
            if (flag) {
                return 1
            }
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "choose", in: module, interner: ctx.interner)

            // After a returnValue instruction, there should be no copy to the if-result
            // that uses a Nothing-typed dead expression as source.
            var foundReturnInBranch = false
            var deadCopyAfterReturn = false
            for (index, instruction) in body.enumerated() {
                if case .returnValue = instruction {
                    foundReturnInBranch = true
                    // Check if the next non-label instruction is a copy
                    var nextIndex = index + 1
                    while nextIndex < body.count {
                        if case .label = body[nextIndex] {
                            nextIndex += 1
                            continue
                        }
                        if case .copy = body[nextIndex] {
                            deadCopyAfterReturn = true
                        }
                        break
                    }
                }
            }
            XCTAssertTrue(foundReturnInBranch, "Expected returnValue in if-branch")
            XCTAssertFalse(deadCopyAfterReturn, "No dead copy should follow a returnValue instruction in a terminated branch")
        }
    }

    func testFunctionTypedMemberPropertyCallKeepsPropertyCalleeName() throws {
        let source = """
        class Holder {
            val transform: (Int) -> Int = { it + 1 }
        }
        fun use(h: Holder): Int = h.transform(5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("transform"),
                "Expected property callee name 'transform', got: \(callees)"
            )
            XCTAssertFalse(
                callees.contains("invoke"),
                "Function-typed property calls must not be rewritten to 'invoke'."
            )
        }
    }
}
