#if canImport(Testing)
import Testing
@testable import CompilerCore

@Suite struct AbstractOpenOverrideTests {

    // MARK: - Shared Sema contexts

    private static let positiveSources: [String] = [
        """
        package sample0
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "I am a shape"
        }
        class Circle(val r: Double) : Shape() {
            override fun area(): Double = 3.14159 * r * r
            override fun describe(): String = "Circle"
        }
        class Rect(val w: Double, val h: Double) : Shape() {
            override fun area(): Double = w * h
        }
        fun main() {
            val c = Circle(5.0)
            println(c.describe())
            println(c.area())
            val r = Rect(3.0, 4.0)
            println(r.describe())
            println(r.area())
        }
        """,
        """
        package sample1
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "Shape"
        }

        abstract class RegularShape : Shape() {
            abstract override fun area(): Double
            override fun describe(): String = "Regular Shape"
        }

        class Circle(val r: Double) : RegularShape() {
            override fun area(): Double = 3.14159 * r * r
            final override fun describe(): String = "Circle"
        }
        """,
        """
        package sample2
        interface CommandProcessor {
            val pluginId: String
            val displayName: String
        }

        class MyCommandProcessor(
            override val pluginId: String,
            override val displayName: String
        ) : CommandProcessor

        fun main() {
            val p = MyCommandProcessor("id", "name")
            println(p.pluginId)
        }
        """,
        """
        package sample3
        abstract class Container {
            abstract var items: List<String>
        }

        class Box(override var items: List<String>) : Container()
        """,
        """
        package sample4
        interface CommandProcessor {
            val pluginId: String
            val displayName: String
        }

        class MyCommandProcessor(
            override val pluginId: String
        ) : CommandProcessor {
            override val displayName: String = "static-name"
        }
        """,
    ]

    private static let negativeSources: [String] = [
        """
        package sample5
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "I am a shape"
        }
        class Circle(val r: Double) : Shape() {
            // Missing override for abstract area()
            override fun describe(): String = "Circle"
        }
        """,
        """
        package sample6
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "I am a shape"
        }
        class Circle(val r: Double) : Shape() {
            override fun area(): Double = 3.14159 * r * r
            fun describe(): String = "Circle" // Missing override modifier
        }
        """,
        """
        package sample7
        open class Shape {
            open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            final override fun describe(): String = "Circle"
        }

        // This should error - cannot override final
        class ColoredCircle : Circle() {
            override fun describe(): String = "Colored Circle"
        }
        """,
        """
        package sample8
        interface CommandProcessor {
            val pluginId: String
            val displayName: String
        }

        class MyCommandProcessor(
            val pluginId: String
        ) : CommandProcessor
        """,
    ]

    private static nonisolated(unsafe) var _positiveCtx: CompilationContext?
    private static nonisolated(unsafe) var _negativeCtx: CompilationContext?

    private func positiveCtx() throws -> CompilationContext {
        if let cached = Self._positiveCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.positiveSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._positiveCtx = ctx
        return ctx
    }

    private func negativeCtx() throws -> CompilationContext {
        if let cached = Self._negativeCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.negativeSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._negativeCtx = ctx
        return ctx
    }

    // MARK: - Original Test Case Validation

    @Test func testOriginalAbstractOpenOverrideCase() throws {
        let ctx = try positiveCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testMissingAbstractOverride() throws {
        let ctx = try negativeCtx()

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testMissingOverrideModifier() throws {
        let ctx = try negativeCtx()

        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: ctx)
    }

    // MARK: - Advanced Test Cases

    @Test func testAbstractOverrideChaining() throws {
        let ctx = try positiveCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testFinalOverrideTermination() throws {
        let ctx = try negativeCtx()

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    // MARK: - Primary constructor `override val` / `override var` properties

    @Test func testPrimaryConstructorOverridePropertiesImplementInterface() throws {
        let ctx = try positiveCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testPrimaryConstructorOverrideVarPropertyImplementsAbstractClassMember() throws {
        let ctx = try positiveCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testMixedPrimaryConstructorAndBodyOverrideProperties() throws {
        let ctx = try positiveCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testMissingPrimaryConstructorOverrideStillReportsAbstractMember() throws {
        let ctx = try negativeCtx()

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testPrimaryConstructorOpenPropertyCanBeOverridden() throws {
        let source = """
        open class Base(open val p: String)

        class Derived(p: String) : Base(p) {
            override val p: String = p + "!"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

}
#endif
