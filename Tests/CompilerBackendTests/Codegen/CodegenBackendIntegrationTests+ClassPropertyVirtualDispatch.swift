#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// BUG-227 regression coverage: an open/abstract/override *class* property
// (stored, custom-getter, or custom-setter) read or written through a
// base-typed reference must dispatch to the actual runtime type's accessor,
// exactly like an ordinary open/override method already does. Before the
// fix, `tryLowerStoredMemberPropertyRead`/`tryLowerMemberPropertyAccessorRead`/
// `lowerMemberAssignExpr`/`lowerMemberCompoundAssignExpr` resolved the
// accessor purely from the receiver's *static* type and LayoutSynthesis never
// gave a property accessor a vtable slot, so a base-typed reference always
// observed the base declaration's own storage/accessor — basic class
// inheritance polymorphism was broken for properties while working correctly
// for methods.
private func runClassPropertyVirtualDispatchCodegenPipeline(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
        target: defaultTargetTriple()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

@Suite
struct CodegenBackendClassPropertyVirtualDispatchTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runClassPropertyVirtualDispatchCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testStoredPropertyReadThroughBaseTypedReference() throws {
        // The canonical minimal repro from TODO.md BUG-227.
        let source = """
        open class Base {
            open val p = "bp"
            open fun f() = "base"
        }
        class Derived : Base() {
            override val p = "dp"
            override fun f() = "derived"
        }
        fun main() {
            val b: Base = Derived()
            println(b.p)
            println(b.f())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223StoredPropertyRead",
            expected: "dp\nderived\n"
        )
    }

    @Test
    func testCustomGetterOverrideReadThroughBaseTypedReference() throws {
        let source = """
        open class Base {
            open val p: String get() = "bp"
        }
        class Derived : Base() {
            override val p: String get() = "dp"
        }
        fun main() {
            val b: Base = Derived()
            println(b.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223CustomGetterRead",
            expected: "dp\n"
        )
    }

    @Test
    func testCustomSetterOverrideWriteAndReadThroughBaseTypedReference() throws {
        let source = """
        open class Base {
            open var p: String = "base-init"
                set(value) { field = "base:" + value }
        }
        class Derived : Base() {
            override var p: String = "derived-init"
                set(value) { field = "derived:" + value }
        }
        fun main() {
            val b: Base = Derived()
            b.p = "x"
            println(b.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223CustomSetterWrite",
            expected: "derived:x\n"
        )
    }

    @Test
    func testIntTypedStoredPropertyVirtualDispatchDoesNotCorruptBoxing() throws {
        let source = """
        open class Base {
            open var p: Int = 1
        }
        class Derived : Base() {
            override var p: Int = 2
        }
        fun main() {
            val b: Base = Derived()
            println(b.p)
            b.p = 99
            println(b.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223IntPropertyBoxing",
            expected: "2\n99\n"
        )
    }

    @Test
    func testAbstractPropertyOverrideReadThroughBaseTypedReference() throws {
        let source = """
        abstract class Shape {
            abstract val area: Double
        }
        class Square(val side: Double) : Shape() {
            override val area: Double get() = side * side
        }
        fun main() {
            val s: Shape = Square(3.0)
            println(s.area)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223AbstractPropertyRead",
            expected: "9.0\n"
        )
    }

    @Test
    func testAbstractPropertyReadInsideBaseMethodUsesGetterDispatch() throws {
        let source = """
        abstract class Shape {
            abstract val area: Double
            fun doubledArea(): Double = area * 2.0
        }
        class Square(private val side: Double) : Shape() {
            override val area: Double get() = side * side
        }
        fun main() {
            val shape: Shape = Square(3.0)
            println(shape.doubledArea())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223AbstractPropertyInsideBaseMethod",
            expected: "18.0\n"
        )
    }

    @Test
    func testDirectlyTypedReceiverStillReadsItsOwnOverrideDirectly() throws {
        // Non-polymorphic access (no upcast) was already correct before the
        // fix; pin it so virtualizing the base-typed path doesn't regress it.
        let source = """
        open class Base {
            open val p = "bp"
        }
        class Derived : Base() {
            override val p = "dp"
        }
        fun main() {
            val d = Derived()
            println(d.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223DirectReceiverRead",
            expected: "dp\n"
        )
    }

    @Test
    func testCanonicalDiffCaseClassPropertyVirtualDispatch() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerBackendTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/class_property_virtual_dispatch.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "Bug223ClassPropertyVirtualDispatch",
            expected:
                """
                dp
                derived
                dp
                derived:x
                9.0
                """ + "\n"
        )
    }
}
#endif
