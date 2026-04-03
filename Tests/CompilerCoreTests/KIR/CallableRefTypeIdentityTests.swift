@testable import CompilerCore
import Foundation
import XCTest

/// REFL-003: Tests for KFunction / KProperty type identity on callable references.
final class CallableRefTypeIdentityTests: XCTestCase {
    // MARK: - Sema binding tests

    func testSemaBindsFunctionRefKindForCallableReference() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main() {
            val f = ::inc
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callableRefExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        XCTAssertEqual(refKind, .functionRef, "::inc should be marked as a function reference.")
    }

    func testSemaBindsPropertyRefKindForPropertyCallableReference() throws {
        let source = """
        val answer: Int = 42
        fun main() {
            val ref = ::answer
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callableRefExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        XCTAssertEqual(refKind, .propertyRef, "::answer should be marked as a property reference.")
    }

    func testSemaBindsFunctionRefKindForBoundCallableReference() throws {
        let source = """
        class Box {
            fun value(): Int = 42
        }
        fun main(box: Box) {
            val f = box::value
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callableRefExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        XCTAssertEqual(refKind, .functionRef, "box::value should be marked as a function reference.")
    }

    func testSemaBindsFunctionRefKindForOverloadedCallableReference() throws {
        let source = """
        fun target(x: Int): Int = x + 1
        fun target(x: String): String = x
        fun main() {
            val ref: (Int) -> Int = ::target
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callableRefExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        XCTAssertEqual(refKind, .functionRef, "Overloaded ::target should be marked as a function reference.")
    }

    // MARK: - KIR lowering tests

    func testKIREmitsKFunctionTagForFunctionCallableRef() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_callable_ref_tag_kfunction"),
                "KIR main body should contain kk_callable_ref_tag_kfunction call. Callees: \(callees)"
            )
        }
    }

    func testKIREmitsKPropertyTagForPropertyCallableRef() throws {
        let source = """
        val answer: Int = 42
        fun main(): Int {
            val ref = ::answer
            return answer
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            // Property callable refs are lowered inline in main.
            let allCallees = module.arena.declarations.flatMap { decl -> [String] in
                guard case let .function(function) = decl else { return [] }
                return extractCallees(from: function.body, interner: ctx.interner)
            }
            // Verify the property ref is tagged with the KProperty tag.
            XCTAssertTrue(
                allCallees.contains("kk_callable_ref_tag_kproperty"),
                "Property callable ref should be tagged as KProperty. Callees: \(allCallees)"
            )
            // Verify it does not accidentally tag as kfunction.
            XCTAssertFalse(
                allCallees.contains("kk_callable_ref_tag_kfunction"),
                "Property callable ref should NOT be tagged as KFunction."
            )
        }
    }

    func testKIRKFunctionTagIncludesCorrectNameAndArity() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main(): Int {
            val f = ::add
            return f(1, 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            // Find the tagging call and verify its arguments.
            let tagCall = mainBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
            }
            guard case let .call(_, _, arguments, _, _, _, _, _) = tagCall else {
                XCTFail("Expected kk_callable_ref_tag_kfunction call in main body.")
                return
            }

            // arguments[0] = callable value, arguments[1] = name, arguments[2] = arity, arguments[3] = isSuspend
            XCTAssertEqual(arguments.count, 4)

            // Verify the name argument is the string "add".
            if let nameExpr = module.arena.expr(arguments[1]),
               case let .stringLiteral(nameInterned) = nameExpr
            {
                XCTAssertEqual(ctx.interner.resolve(nameInterned), "add")
            } else {
                XCTFail("Second argument to tag call should be string literal 'add'.")
            }

            // Verify the arity argument is 2 (two value parameters).
            if let arityExpr = module.arena.expr(arguments[2]),
               case let .intLiteral(arityValue) = arityExpr
            {
                XCTAssertEqual(arityValue, 2, "::add has arity 2 (a, b).")
            } else {
                XCTFail("Third argument to tag call should be int literal for arity.")
            }

            // Verify the suspend flag is false for a regular function reference.
            if let suspendExpr = module.arena.expr(arguments[3]),
               case let .intLiteral(isSuspendValue) = suspendExpr
            {
                XCTAssertEqual(isSuspendValue, 0, "::add is not suspend.")
            } else {
                XCTFail("Fourth argument to tag call should be int literal for suspend flag.")
            }
        }
    }

    func testKIRKFunctionTagForBoundCallableRef() throws {
        let source = """
        class Box {
            fun plus(x: Int): Int = x
        }
        fun main(box: Box): Int {
            val f = box::plus
            return f(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_callable_ref_tag_kfunction"),
                "Bound callable ref box::plus should emit KFunction tag. Callees: \(callees)"
            )
        }
    }

    // MARK: - Non-throwing verification

    func testCallableRefTagCallsAreNonThrowing() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let tagCall = mainBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
            }
            guard case let .call(_, _, _, _, canThrow, _, _, _) = tagCall else {
                XCTFail("Expected kk_callable_ref_tag_kfunction call.")
                return
            }
            XCTAssertFalse(canThrow, "Callable ref tagging call should be non-throwing.")
        }
    }
}
