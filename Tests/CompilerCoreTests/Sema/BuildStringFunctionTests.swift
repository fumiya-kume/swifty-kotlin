@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-006: Validates that `buildString` (kotlin.text inline builder) resolves
/// through Sema and produces `String` return type. The runtime lowers `buildString { }` to
/// `kk_build_string` and the optional capacity overload to `kk_build_string_with_capacity`.
final class BuildStringFunctionTests: XCTestCase {

    // MARK: - Basic resolution

    func testBuildStringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun greeting(): String = buildString {
            append("Hello, ")
            append("world!")
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "buildString { } should resolve without errors, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testBuildStringReturnTypeIsString() throws {
        // buildString must return String so subsequent String members resolve.
        let ctx = makeContextFromSource("""
        fun lengthOfBuilt(): Int {
            return buildString { append("abc") }.length
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "buildString return type should be String (length should resolve), got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testBuildStringAssignableToString() throws {
        let ctx = makeContextFromSource("""
        fun build(): String {
            val s: String = buildString { append("x") }
            return s
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "buildString result should be assignable to String, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - Capacity overload

    func testBuildStringWithPositionalCapacityResolves() throws {
        let ctx = makeContextFromSource("""
        fun withCapacity(): String = buildString(64) {
            append("capacity hint")
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "buildString(capacity) should resolve without errors, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testBuildStringWithNamedCapacityResolves() throws {
        let ctx = makeContextFromSource("""
        fun withNamedCapacity(): String = buildString(capacity = 16) {
            append("named capacity")
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "buildString(capacity=N) should resolve without errors, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - Implicit receiver (this)

    func testBuildStringImplicitReceiverAppend() throws {
        let ctx = makeContextFromSource("""
        fun withImplicitReceiver(): String = buildString {
            this.append("explicit this")
            append("implicit")
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "buildString block should allow both explicit this and implicit receiver calls, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - Nested usage

    func testBuildStringNestedInExpression() throws {
        let ctx = makeContextFromSource("""
        fun nested(): String {
            val prefix = "pre"
            return prefix + buildString { append("suffix") }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "buildString nested in expression should resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - Builder DSL kind binding

    func testBuildStringIsMarkedAsBuilderDSL() throws {
        let source = """
        fun build(): String = buildString { append("test") }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "buildString should resolve, got: \(ctx.diagnostics.diagnostics)")

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)

        let callID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .call(calleeID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeID),
                  case let .nameRef(name, _) = calleeExpr
            else { return false }
            return ctx.interner.resolve(name) == "buildString"
        }, "Expected a call to buildString in the AST")

        let kind = sema.bindings.builderDSLKind(for: callID)
        XCTAssertEqual(kind, .buildString, "buildString call should be bound as .buildString DSL kind")
    }
}
