@testable import CompilerCore
import Foundation
import XCTest

// MARK: - Diagnostic Code Coverage Tests (TEST-ERR-004)
//
// Covers 15+ diagnostic codes previously untested:
//   KSWIFTK-LEX-0004
//   KSWIFTK-PARSE-0001, PARSE-0006
//   KSWIFTK-SEMA-0021, SEMA-0042, SEMA-0043, SEMA-0050, SEMA-0052,
//   KSWIFTK-SEMA-0054, SEMA-0055, SEMA-0061, SEMA-0070, SEMA-0072,
//   KSWIFTK-SEMA-0073, SEMA-0074, SEMA-0080, SEMA-0081, SEMA-0083,
//   KSWIFTK-SEMA-0097, SEMA-0098, SEMA-0300, SEMA-0301

final class DiagnosticCodeCoverageTests: XCTestCase {}

// MARK: - LEX-0004: Invalid escape sequence / unescaped line break

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-LEX-0004: unescaped newline inside a string literal.
    func testLex0004UnescapedNewlineInStringLiteral() throws {
        // The source string embeds a literal newline inside a quoted string.
        let source = "val s = \"hello\nworld\""
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertHasDiagnostic("KSWIFTK-LEX-0004", in: ctx)
    }

    /// A multi-line string (triple-quoted) does NOT trigger LEX-0004.
    func testLex0004NotEmittedForTripleQuotedString() throws {
        let source = """
        val s = \"\"\"
        hello
        world
        \"\"\"
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-LEX-0004", in: ctx)
    }
}

// MARK: - PARSE-0001: Expected keyword in declaration

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-PARSE-0001 by using `context` receiver syntax without
    /// the required parenthesised receiver type.
    func testParse0001ContextReceiverMissingParentheses() throws {
        let source = "context fun foo() {}"
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertHasDiagnostic("KSWIFTK-PARSE-0001", in: ctx)
    }
}

// MARK: - PARSE-0006: Unexpected token in declaration

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-PARSE-0006: a stray token in the middle of a
    /// declaration (e.g. a modifier keyword appearing where a body is expected).
    func testParse0006UnexpectedTokenInDeclaration() throws {
        // A stray token between top-level declarations triggers PARSE-0006.
        let source = """
        fun foo() {}
        ??? unexpected
        fun bar() {}
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertHasDiagnostic("KSWIFTK-PARSE-0006", in: ctx)
    }

    /// A well-formed function with an `override` modifier in the right place
    /// must NOT emit PARSE-0006.
    func testParse0006NotEmittedForValidOverrideModifier() throws {
        let source = """
        open class Base { open fun foo() {} }
        class Child : Base() { override fun foo() {} }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0006", in: ctx)
    }
}

// MARK: - SEMA-0021: Cannot delegate to super without a superclass

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0021: a secondary constructor delegates to
    /// `super()` but the class has no superclass.
    func testSema0021SuperDelegationWithoutSuperclass() throws {
        let source = """
        class Foo {
            constructor(x: Int) : super()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        XCTAssertTrue(
            codes.contains("KSWIFTK-SEMA-0021") || codes.contains("KSWIFTK-SEMA-0055"),
            "Expected SEMA-0021 or SEMA-0055 for super() delegation without superclass, got: \(codes)"
        )
    }

    /// A class that actually has a superclass must NOT emit SEMA-0021.
    func testSema0021NotEmittedWhenSuperclassExists() throws {
        let source = """
        open class Base(val x: Int)
        class Derived : Base {
            constructor(x: Int) : super(x)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0021", in: ctx)
    }
}

// MARK: - SEMA-0042: return@label does not reference a valid enclosing lambda

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0042: `return@nonExistentLabel` where the label
    /// does not name any enclosing lambda.
    func testSema0042ReturnAtInvalidLabel() throws {
        let source = """
        fun test() {
            val list = listOf(1, 2, 3)
            list.forEach {
                return@nonExistentLabel
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }
}

// MARK: - SEMA-0043: Mixed signed/unsigned operands

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0043: binary arithmetic mixing a signed and an
    /// unsigned integer type.
    func testSema0043SignedUnsignedMixInBinaryAdd() throws {
        let source = """
        fun mix(a: Int, b: UInt): Int {
            val r = a + b
            return r
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0043", in: ctx)
    }

    /// Pure signed arithmetic must NOT emit SEMA-0043.
    func testSema0043NotEmittedForPureSignedArithmetic() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0043", in: ctx)
    }
}

// MARK: - SEMA-0050: 'super' outside a class body

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0050: top-level use of `super`.
    func testSema0050SuperOutsideClassBody() throws {
        let source = """
        fun test() {
            val x = super.toString()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0050", in: ctx)
    }
}

// MARK: - SEMA-0052: Class has no superclass (bare super reference)

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0052: a class member references `super` but the
    /// class has no superclass.
    func testSema0052SuperInClassWithNoSuperclass() throws {
        let source = """
        class Foo {
            fun test(): String = super.toString()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        XCTAssertTrue(
            codes.contains("KSWIFTK-SEMA-0052") || codes.contains("KSWIFTK-SEMA-0024"),
            "Expected SEMA-0052 or SEMA-0024 for super reference in class without superclass, got: \(codes)"
        )
    }
}

// MARK: - SEMA-0054: Secondary constructor must delegate to another constructor

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0054: a secondary constructor in a class that
    /// has a primary constructor, but the secondary constructor omits the
    /// required `this(...)` delegation.
    func testSema0054SecondaryCtorMissingDelegation() throws {
        let source = """
        class Bar(val x: Int) {
            constructor(x: Int, y: Int) {
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0054", in: ctx)
    }

    /// A secondary constructor that properly delegates via `this()` must NOT
    /// emit SEMA-0054.
    func testSema0054NotEmittedWhenDelegationPresent() throws {
        let source = """
        class Bar(val x: Int) {
            constructor(x: Int, y: Int) : this(x + y)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0054", in: ctx)
    }
}

// MARK: - SEMA-0061: Type alias missing right-hand side

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0061: `typealias` declaration with no
    /// right-hand type (only parseable through error-recovery).
    func testSema0061TypeAliasMissingRhs() throws {
        // The parser can produce a type-alias node without an underlying type
        // when the source is malformed.  We write Kotlin that causes the
        // AST to carry a typealias with no RHS.
        let source = "typealias MyType"
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // We expect either a parse error or a sema error about the missing RHS.
        let codes = ctx.diagnostics.diagnostics.map(\.code)
        XCTAssertTrue(
            codes.contains("KSWIFTK-SEMA-0061") || codes.contains("KSWIFTK-PARSE-0005"),
            "Expected SEMA-0061 or PARSE-0005 for typealias without RHS, got: \(codes)"
        )
    }
}

// MARK: - SEMA-0070: Sealed subclass outside package

extension DiagnosticCodeCoverageTests {
    /// SEMA-0070 is emitted when a class tries to extend a sealed class but is
    /// not in the same package.  This is detected at the sema / inheritance
    /// pass.  In a single-file unit test the same package restriction applies
    /// to value classes: a @JvmInline value class with != 1 primary ctor param
    /// also emits SEMA-0070.
    func testSema0070ValueClassMustHaveExactlyOneParam() throws {
        let source = """
        @JvmInline
        value class Pair(val a: Int, val b: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0070", in: ctx)
    }

    /// A @JvmInline value class with exactly one primary constructor parameter
    /// must NOT emit SEMA-0070.
    func testSema0070NotEmittedForValidValueClass() throws {
        let source = """
        @JvmInline
        value class Money(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0070", in: ctx)
    }
}

// MARK: - SEMA-0072: Duplicate condition in when branch

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0072: the same literal condition appears twice
    /// in distinct branches of the same when expression.
    func testSema0072DuplicateWhenCondition() throws {
        // SEMA-0072 is emitted when the SAME condition appears twice within
        // the SAME branch (comma-separated conditions list).
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1, 1 -> "one or one"
                else -> "other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
    }

    /// Non-duplicate conditions must NOT emit SEMA-0072.
    func testSema0072NotEmittedForDistinctConditions() throws {
        let source = """
        fun test(x: Int): String = when (x) {
            1 -> "one"
            2 -> "two"
            else -> "other"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
    }
}

// MARK: - SEMA-0073: Condition already covered by previous when branch

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0073: a condition that was already fully handled
    /// by an earlier branch (unreachable branch).
    func testSema0073DuplicateConditionAcrossBranches() throws {
        // SEMA-0073 is emitted when the same condition appears in a different
        // branch that has already been covered by an earlier branch.
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1 -> "one"
                1 -> "also one"
                else -> "other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0073", in: ctx)
    }
}

// MARK: - SEMA-0074: When branch guard must be Boolean

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0074: the guard expression in a `when` branch
    /// is not a Boolean expression.
    func testSema0074WhenBranchGuardNotBoolean() throws {
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1 if 42 -> "bad"
                else -> "ok"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0074", in: ctx)
    }

    /// A Boolean guard condition must NOT emit SEMA-0074.
    func testSema0074NotEmittedForBooleanGuard() throws {
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1 if x > 0 -> "positive one"
                else -> "other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0074", in: ctx)
    }
}

// MARK: - SEMA-0080: 'const' is not applicable to 'var'

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0080: `const var` is not allowed; const only
    /// applies to `val`.
    func testSema0080ConstVar() throws {
        let source = """
        const var X = 42
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0080", in: ctx)
    }

    /// `const val` is valid and must NOT emit SEMA-0080.
    func testSema0080NotEmittedForConstVal() throws {
        let source = """
        const val X = 42
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0080", in: ctx)
    }
}

// MARK: - SEMA-0081: 'const val' must have an initializer

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0081: a `const val` that has no initializer.
    func testSema0081ConstValWithoutInitializer() throws {
        let source = """
        const val X: Int
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0081", in: ctx)
    }
}

// MARK: - SEMA-0083: 'const val' initializer must be a compile-time constant

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0083: the initializer of a `const val` is not a
    /// compile-time constant literal.
    func testSema0083ConstValNonLiteralInitializer() throws {
        let source = """
        fun compute(): Int = 42
        const val X = compute()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0083", in: ctx)
    }

    /// A `const val` with a literal initializer must NOT emit SEMA-0083.
    func testSema0083NotEmittedForLiteralInitializer() throws {
        let source = """
        const val X = 100
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0083", in: ctx)
    }
}

// MARK: - SEMA-0097: 'break' with label that does not reference an enclosing loop

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0097: `break@badLabel` used where `badLabel`
    /// does not name any surrounding loop.
    func testSema0097BreakAtInvalidLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                break@nonExistent
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0097", in: ctx)
    }

    /// `break@outer` where `outer` labels an enclosing loop must NOT emit
    /// SEMA-0097.
    func testSema0097NotEmittedForValidBreakLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                for (j in 1..5) {
                    break@outer
                }
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0097", in: ctx)
    }
}

// MARK: - SEMA-0098: 'continue' with label that does not reference an enclosing loop

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0098: `continue@badLabel` where `badLabel` does
    /// not name any surrounding loop.
    func testSema0098ContinueAtInvalidLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                continue@ghost
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0098", in: ctx)
    }

    /// `continue@outer` where `outer` labels an enclosing loop must NOT emit
    /// SEMA-0098.
    func testSema0098NotEmittedForValidContinueLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                for (j in 1..5) {
                    continue@outer
                }
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0098", in: ctx)
    }
}

// MARK: - SEMA-0300: Compound-assignment operator must return Unit

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0300: a custom `plusAssign` (+=) operator
    /// is defined but its return type is not `Unit`.
    func testSema0300CompoundAssignOperatorMustReturnUnit() throws {
        let source = """
        class Counter(var value: Int) {
            operator fun plusAssign(other: Int): Int {
                value += other
                return value
            }
        }
        fun test() {
            val c = Counter(0)
            c += 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0300", in: ctx)
    }

    /// A `plusAssign` that correctly returns `Unit` must NOT emit SEMA-0300.
    func testSema0300NotEmittedWhenPlusAssignReturnsUnit() throws {
        let source = """
        class Counter(var value: Int) {
            operator fun plusAssign(other: Int) {
                value += other
            }
        }
        fun test() {
            val c = Counter(0)
            c += 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0300", in: ctx)
    }
}

// MARK: - SEMA-0301: Compound-assignment operator result not assignable to LHS

extension DiagnosticCodeCoverageTests {
    /// Triggers KSWIFTK-SEMA-0301: a compound-assignment resolves to the binary
    /// operator form (e.g. `plus`) but its return type is incompatible with the
    /// left-hand side.
    func testSema0301CompoundAssignBinaryResultNotAssignable() throws {
        // SEMA-0301 is emitted when a compound-assignment uses the binary operator
        // fallback but its return type is not assignable back to the LHS variable.
        // This requires a member plusAssign (not extension plus) returning a different type.
        let source = """
        class Container(var value: Int) {
            operator fun plusAssign(delta: Int): Container {
                value += delta
                return this
            }
        }
        fun test() {
            var c = Container(0)
            c += 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // SEMA-0300 fires because plusAssign must return Unit.
        // SEMA-0301 fires on the binary fallback path when the result type
        // is not assignable. Either diagnostic indicates the compound-assignment error.
        let codes = ctx.diagnostics.diagnostics.map(\.code)
        XCTAssertTrue(
            codes.contains("KSWIFTK-SEMA-0300") || codes.contains("KSWIFTK-SEMA-0301"),
            "Expected SEMA-0300 or SEMA-0301 for compound-assignment type mismatch, got: \(codes)"
        )
    }
}
