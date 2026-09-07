#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// REFL-003: Tests for KFunction / KProperty type identity on callable references.
@Suite
struct CallableRefTypeIdentityTests {
    // MARK: - Sema binding tests

    @Test func testSemaBindsFunctionRefKindForCallableReference() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main() {
            val f = ::inc
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "::inc should be marked as a function reference.")
    }

    @Test func testSemaBindsPropertyRefKindForPropertyCallableReference() throws {
        let source = """
        val answer: Int = 42
        fun main() {
            val ref = ::answer
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .propertyRef, "::answer should be marked as a property reference.")
    }

    @Test func testSemaBindsFunctionRefKindForBoundCallableReference() throws {
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

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "box::value should be marked as a function reference.")
    }

    @Test func testSemaBindsFunctionRefKindForOverloadedCallableReference() throws {
        let source = """
        fun target(x: Int): Int = x + 1
        fun target(x: String): String = x
        fun main() {
            val ref: (Int) -> Int = ::target
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "Overloaded ::target should be marked as a function reference.")
    }

    // MARK: - Generic call-site type inference tests

    /// KSP-496 (found as a side-effect while validating a property callable-ref
    /// Sema fix): a property callable reference passed directly into a generic
    /// call (e.g. `listOf<T>(vararg elements: T)`) used to be type-checked
    /// against the *unsubstituted* type parameter `T` rather than its own
    /// natural `KProperty1<Owner, Value>` type, because `inferCallableRefExpr`
    /// adopted `expectedType` verbatim even when it still mentioned a type
    /// parameter. Binding the reference's static type to a bare type variable
    /// made `lowerPropertyReferenceWrapperValue` (which requires a resolved
    /// `KProperty*` classType) bail out and fall back to a legacy bare-symbol
    /// callable path that crashes at runtime (calls the raw property accessor
    /// with no receiver — see `Scripts/diff_cases/kproperty_generic_vararg_inference.kt`
    /// for the end-to-end runtime regression).
    @Test func testUnboundPropertyRefInGenericVarargCallGetsConcreteKProperty1Type() throws {
        let source = """
        class Counter(val v: Int)
        fun main() {
            val list = listOf(Counter::v)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let kProperty1Symbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "reflect", "KProperty1"].map { interner.intern($0) })
        )

        let boundType = try #require(sema.bindings.exprType(for: callableRefExprID))
        guard case let .classType(classType) = sema.types.kind(of: boundType) else {
            Issue.record(
                "Counter::v inside listOf(...) should bind to a KProperty1 classType, got \(sema.types.renderType(boundType))"
            )
            return
        }
        #expect(
            classType.classSymbol == kProperty1Symbol,
            "Counter::v inside listOf(...) should bind to kotlin.reflect.KProperty1, not an unsubstituted type parameter."
        )
        #expect(classType.args.count == 2, "KProperty1<Counter, Int> should carry both type arguments.")
    }

    // MARK: - KIR lowering tests

    @Test func testKIREmitsKFunctionTagForFunctionCallableRef() throws {
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

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("kk_callable_ref_tag_kfunction"),
                "KIR main body should contain kk_callable_ref_tag_kfunction call. Callees: \(callees)"
            )
        }
    }

    /// KSP-496 follow-up: a bare `::member` reference to a member property
    /// of the enclosing class must capture the implicit `this` receiver into
    /// the generated KProperty wrapper object, the same way an explicit
    /// `this::member` reference does — otherwise `.get()`/`.set()` on the
    /// wrapper has no instance to read/write and crashes at runtime. This
    /// checks the KIR-level signal for that capture: a `kk_array_set` store
    /// into the wrapper's capture slot, which only exists when there's a
    /// non-empty capture argument list.
    @Test func testKIRCapturesImplicitReceiverForBareMemberPropertyRef() throws {
        let source = """
        class C(val v: Int) {
            fun r(): Int {
                val ref = ::v
                return ref.get()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let rBody = try findKIRFunctionBody(named: "r", in: module, interner: ctx.interner)
            let callees = extractCallees(from: rBody, interner: ctx.interner)

            #expect(
                callees.contains("kk_array_set"),
                "Expected the bare ::v reference's wrapper to store a captured receiver (kk_array_set). Callees: \(callees)"
            )
        }
    }

    @Test func testKIREmitsKPropertyTagForPropertyCallableRef() throws {
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

            let module = try #require(ctx.kir)
            // Property callable refs are lowered inline in main.
            let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                return extractCallees(from: function.body, interner: ctx.interner)
            }
            // Verify the property ref is tagged with the KProperty tag.
            #expect(
                allCallees.contains("kk_callable_ref_tag_kproperty"),
                "Property callable ref should be tagged as KProperty. Callees: \(allCallees)"
            )
            // Verify it does not accidentally tag as kfunction.
            #expect(
                !(allCallees.contains("kk_callable_ref_tag_kfunction")),
                "Property callable ref should NOT be tagged as KFunction."
            )
        }
    }

    @Test func testKIRKFunctionTagIncludesCorrectNameAndArity() throws {
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

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            // Find the tagging call and verify its arguments.
            let tagCall = mainBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
            }
            guard case let .call(_, _, arguments, _, _, _, _, _) = tagCall else {
                Issue.record("Expected kk_callable_ref_tag_kfunction call in main body.")
                return
            }

            // arguments[0] = callable value, arguments[1] = name,
            // arguments[2] = return type, arguments[3] = arity,
            // arguments[4] = isSuspend flag.
            #expect(arguments.count == 5)

            // Verify the name argument is the string "add".
            if let nameExpr = module.arena.expr(arguments[1]),
               case let .stringLiteral(nameInterned) = nameExpr
            {
                #expect(ctx.interner.resolve(nameInterned) == "add")
            } else {
                Issue.record("Second argument to tag call should be string literal 'add'.")
            }

            // Verify the return type argument is the compact Int descriptor.
            if let returnTypeExpr = module.arena.expr(arguments[2]),
               case let .stringLiteral(returnTypeInterned) = returnTypeExpr
            {
                #expect(ctx.interner.resolve(returnTypeInterned) == "Int")
            } else {
                Issue.record("Third argument to tag call should be string literal 'Int'.")
            }

            // Verify the arity argument is 2 (two value parameters).
            if let arityExpr = module.arena.expr(arguments[3]),
               case let .intLiteral(arityValue) = arityExpr
            {
                #expect(arityValue == 2, "::add has arity 2 (a, b).")
            } else {
                Issue.record("Fourth argument to tag call should be int literal for arity.")
            }

            // Non-suspend callable refs should emit an isSuspend flag of 0.
            if let suspendExpr = module.arena.expr(arguments[4]),
               case let .intLiteral(isSuspendValue) = suspendExpr
            {
                #expect(isSuspendValue == 0, "::add is not a suspend function.")
            } else {
                Issue.record("Fifth argument to tag call should be int literal for isSuspend.")
            }
        }
    }

    @Test func testKIRKFunctionTagForBoundCallableRef() throws {
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

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("kk_callable_ref_tag_kfunction"),
                "Bound callable ref box::plus should emit KFunction tag. Callees: \(callees)"
            )
        }
    }

    // MARK: - Non-throwing verification

    @Test func testCallableRefTagCallsAreNonThrowing() throws {
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

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let tagCall = mainBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
            }
            guard case let .call(_, _, _, _, canThrow, _, _, _) = tagCall else {
                Issue.record("Expected kk_callable_ref_tag_kfunction call.")
                return
            }
            #expect(!(canThrow), "Callable ref tagging call should be non-throwing.")
        }
    }
}
#endif
