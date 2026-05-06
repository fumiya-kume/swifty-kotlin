@testable import CompilerCore
import Foundation
import XCTest

// MARK: - kotlin.contracts effect model edge case tests
//
// STDLIB-CONTRACT-001: Validates that contract { ... } blocks inside inline
// functions are correctly parsed and that the resulting effect models
// (returns/returnsNotNull/callsInPlace) are stored in the SemanticsModels so
// that smart-cast and definite-assignment analysis can rely on them.

final class KotlinContractsEffectModelTests: XCTestCase {

    // MARK: - returns() implies smart-cast

    /// After `returns() implies (x is String)` the variable `x` should be
    /// narrowed to String, so accessing `.length` must not produce a type
    /// error.
    func testReturnsImpliesIsStringEnablesSmartCast() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun assertIsString(x: Any?) {
            contract {
                returns() implies (x is String)
            }
            if (x !is String) throw IllegalArgumentException()
        }

        fun main() {
            val value: Any? = "hello"
            assertIsString(value)
            println(value.length)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    /// `returns() implies (x != null)` should narrow x from nullable to non-null.
    func testReturnsImpliesNotNullEnablesSmartCast() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun requireNonNull(x: String?) {
            contract {
                returns() implies (x != null)
            }
            if (x == null) throw IllegalArgumentException()
        }

        fun main() {
            val s: String? = "world"
            requireNonNull(s)
            println(s.length)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - returnsNotNull()

    /// A function annotated with `returnsNotNull()` should be recognized by
    /// the compiler so that callers can rely on the non-null guarantee.
    func testReturnsNotNullContractIsRecordedOnFunction() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun nonNullResult(input: String?): String {
            contract { returnsNotNull() }
            return input ?: "default"
        }

        fun main() {
            val r = nonNullResult(null)
            println(r.length)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fnSymbol = sema.symbols.allSymbols().first {
                ctx.interner.resolve($0.name) == "nonNullResult"
            }
            XCTAssertNotNil(fnSymbol, "nonNullResult should be resolved")
            if let sym = fnSymbol {
                XCTAssertTrue(
                    sema.symbols.hasContractReturnsNotNull(for: sym.id),
                    "Expected returnsNotNull contract effect on nonNullResult"
                )
            }
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - callsInPlace(EXACTLY_ONCE) — definite assignment

    /// A `val` assigned inside a lambda passed to `callsInPlace(EXACTLY_ONCE)`
    /// is definitely assigned after the call.  No uninitialized-variable
    /// diagnostic should be emitted.
    func testCallsInPlaceExactlyOnceAllowsDefiniteAssignment() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun runExactlyOnce(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            block()
        }

        fun main() {
            val x: Int
            runExactlyOnce { x = 42 }
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    /// The `callsInPlace` effect is stored in the sema model for all four
    /// InvocationKind values.
    func testCallsInPlaceEffectIsStoredForAllInvocationKinds() throws {
        let kinds: [(name: String, kind: InvocationKind)] = [
            ("runAtMostOnce",   .atMostOnce),
            ("runAtLeastOnce",  .atLeastOnce),
            ("runExactlyOnce",  .exactlyOnce),
            ("runUnknown",      .unknown),
        ]

        for (fnName, expectedKind) in kinds {
            let source = """
            import kotlin.contracts.*

            @OptIn(ExperimentalContracts::class)
            inline fun \(fnName)(block: () -> Unit) {
                contract { callsInPlace(block, InvocationKind.\(expectedKind.rawValue)) }
                block()
            }

            fun main() { \(fnName) { println("ok") } }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)
                let sema = try XCTUnwrap(ctx.sema)
                let fnSymbol = sema.symbols.allSymbols().first {
                    ctx.interner.resolve($0.name) == fnName
                }
                guard let sym = fnSymbol else {
                    XCTFail("Symbol \(fnName) not found")
                    return
                }
                let effects = sema.symbols.contractCallsInPlaceEffects(for: sym.id)
                XCTAssertFalse(
                    effects.isEmpty,
                    "\(fnName): expected callsInPlace effect, got none"
                )
                XCTAssertTrue(
                    effects.contains { $0.kind == expectedKind },
                    "\(fnName): expected kind \(expectedKind), got \(effects.map(\.kind))"
                )
            }
        }
    }

    // MARK: - callsInPlace(AT_LEAST_ONCE) — at least one call

    /// AT_LEAST_ONCE allows the val to be definitely assigned (the block runs
    /// at least once) but later reads must still be safe.
    func testCallsInPlaceAtLeastOnceAssignmentIsValid() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun runAtLeastOnce(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.AT_LEAST_ONCE) }
            block()
        }

        fun main() {
            var count = 0
            runAtLeastOnce { count++ }
            println(count)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - Nested inline functions with contracts

    /// Two layers of inline functions each with their own contracts should
    /// both be accepted without type errors.
    func testNestedInlineFunctionsWithContractsCompile() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun outer(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            inner(block)
        }

        @OptIn(ExperimentalContracts::class)
        inline fun inner(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            block()
        }

        fun main() {
            val result: String
            outer { result = "nested" }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    // MARK: - Contract on infix function

    /// An infix function can carry a contract block; the compiler should
    /// parse it without error and record any declared effect.
    func testContractOnInfixFunctionIsAccepted() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        infix fun String?.mustEqual(expected: String) {
            contract {
                returns() implies (this@mustEqual != null)
            }
            if (this != expected) throw AssertionError()
        }

        fun main() {
            val s: String? = "kotlin"
            s mustEqual "kotlin"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - Contract on operator function

    /// An operator function with a contract block should be accepted and the
    /// function should resolve without type errors.
    func testContractOnOperatorFunctionIsAccepted() throws {
        let source = """
        import kotlin.contracts.*

        class Box(val value: Int)

        @OptIn(ExperimentalContracts::class)
        operator fun Box?.component1(): Int {
            contract { returnsNotNull() }
            return this?.value ?: 0
        }

        fun main() {
            val b: Box? = Box(7)
            println(b.component1())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - Contract violation: EXACTLY_ONCE block not invoked

    /// Kotlin trusts the contract at compile-time and performs no runtime
    /// check. A function that claims EXACTLY_ONCE but invokes the block zero
    /// times is accepted syntactically; no compile-time error is expected.
    func testExactlyOnceContractWithNoInvocationIsNotACompileError() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun claimsExactlyOnce(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            // block intentionally not called — contract violation at runtime,
            // but NOT a compile-time error in Kotlin's trusted-contract model.
        }

        fun main() {
            claimsExactlyOnce { println("maybe") }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // The compiler trusts the declared contract; no error should be
            // emitted at compile time for the violation.
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - returns(value) implies condition

    /// `returns(true) implies (condition)` should allow the compiler to narrow
    /// the subject of `condition` after a call where the boolean result is true.
    func testReturnsTrueImpliesConditionContractIsAccepted() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun isNonNull(x: String?): Boolean {
            contract {
                returns(true) implies (x != null)
            }
            return x != null
        }

        fun main() {
            val s: String? = "contracts"
            if (isNonNull(s)) {
                println(s.length)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    // MARK: - ContractBuilder stubs resolve in symbol table

    /// The compiler must synthesize the full `kotlin.contracts` package with
    /// ContractBuilder, Effect, SimpleEffect, ConditionalEffect, HoldsIn, and
    /// InvocationKind so that user code importing `kotlin.contracts.*` can
    /// resolve these names.
    func testContractBuilderAndInvocationKindSymbolsExist() throws {
        let source = """
        import kotlin.contracts.*

        fun noop() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)

        let contractsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
        ]
        XCTAssertNotNil(
            sema.symbols.lookup(fqName: contractsFQName),
            "kotlin.contracts package should be synthesized"
        )

        let expectedSymbols: [(name: String, kind: SymbolKind)] = [
            ("ContractBuilder", .class),
            ("Effect", .interface),
            ("SimpleEffect", .interface),
            ("ConditionalEffect", .interface),
            ("HoldsIn", .interface),
            ("InvocationKind", .enumClass),
        ]

        for expected in expectedSymbols {
            let fqName = contractsFQName + [ctx.interner.intern(expected.name)]
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName),
                "\(expected.name) should be synthesized inside kotlin.contracts"
            )
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, expected.kind)
        }
    }

    func testHoldsInInterfaceAndBuilderSurfaceAreRegistered() throws {
        let source = """
        import kotlin.contracts.*

        fun noop() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)

        let contractsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
        ]
        let effectSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("Effect")])
        )
        let holdsInSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("HoldsIn")])
        )
        XCTAssertEqual(sema.symbols.symbol(holdsInSymbol)?.kind, .interface)
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: holdsInSymbol).contains(effectSymbol),
            "HoldsIn must extend Effect"
        )
        let holdsInAnnotations = sema.symbols.annotations(for: holdsInSymbol)
        XCTAssertTrue(
            holdsInAnnotations.contains { $0.annotationFQName == "kotlin.contracts.ExperimentalContracts" },
            "HoldsIn should carry ExperimentalContracts"
        )
        XCTAssertTrue(
            holdsInAnnotations.contains { $0.annotationFQName == "kotlin.contracts.ExperimentalExtendedContracts" },
            "HoldsIn should carry ExperimentalExtendedContracts"
        )

        let builderFQName = contractsFQName + [ctx.interner.intern("ContractBuilder")]
        let builderSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: builderFQName))
        let builderType = sema.types.make(.classType(ClassType(
            classSymbol: builderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let holdsInType = sema.types.make(.classType(ClassType(
            classSymbol: holdsInSymbol,
            args: [],
            nullability: .nonNull
        )))
        let holdsInFunction = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: builderFQName + [ctx.interner.intern("holdsIn")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
                return signature.receiverType == builderType
                    && signature.parameterTypes.first == sema.types.booleanType
                    && signature.returnType == holdsInType
            },
            "ContractBuilder.holdsIn should be synthesized"
        )
        XCTAssertTrue(
            sema.symbols.annotations(for: holdsInFunction).contains {
                $0.annotationFQName == "kotlin.contracts.ExperimentalExtendedContracts"
            },
            "ContractBuilder.holdsIn should carry ExperimentalExtendedContracts"
        )
    }

    func testHoldsInBuilderSurfaceResolvesInSourceWithOptIn() throws {
        let source = """
        import kotlin.OptIn
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class, ExperimentalExtendedContracts::class)
        inline fun guarded(flag: Boolean, block: () -> Unit) {
            contract { holdsIn(flag, block) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected holdsIn contract surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }
}
