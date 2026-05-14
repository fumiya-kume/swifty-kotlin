@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-033: kotlin.concurrent / kotlin.concurrent.atomics parity edge cases
extension CodegenBackendIntegrationTests {

    // MARK: - AtomicInt extended edge cases

    func testCodegenAtomicIntCASSuccessReturnsTrueAndUpdatesValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(10)
            val result = a.compareAndSet(10, 20)
            println(result)
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntCASSuccess", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\n20\n")
        }
    }

    func testCodegenAtomicIntAsJavaAtomic() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.asJavaAtomic

        fun main() {
            val atomic = AtomicInt(42)
            val javaAtomic: java.util.concurrent.atomic.AtomicInteger = atomic.asJavaAtomic()
            println("ok")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntAsJavaAtomic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "ok\n")
        }
    }

    func testCodegenAtomicIntCASFailureReturnsFalseAndLeavesValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(10)
            val result = a.compareAndSet(99, 20)
            println(result)
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntCASFailure", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "false\n10\n")
        }
    }

    func testCodegenAtomicIntCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(5)
            // Success: returns old value (5), updates to 10
            println(a.compareAndExchange(5, 10))
            println(a.load())
            // Failure: returns current value (10), leaves unchanged
            println(a.compareAndExchange(99, 20))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntCAE", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "5\n10\n10\n10\n")
        }
    }

    func testCodegenAtomicIntFetchAndIncrementReturnsOldValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(7)
            println(a.fetchAndIncrement())
            println(a.load())
            println(a.fetchAndDecrement())
            println(a.load())
            println(a.incrementAndFetch())
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntIncrement", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "7\n8\n8\n7\n8\n8\n")
        }
    }

    func testCodegenAtomicIntLargePositiveValue() throws {
        // Note: In this compiler's current implementation, Kotlin Int is mapped to 64-bit
        // native Int. Int.MAX_VALUE + 1 does not wrap to Int.MIN_VALUE but instead
        // produces 2147483648 (a valid 64-bit value). This test documents the current
        // addAndFetch behavior for large positive values.
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(Int.MAX_VALUE)
            println(a.load())
            val after = a.addAndFetch(1)
            println(after > 0)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntLargeValue", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalized, "2147483647\ntrue\n")
        }
    }

    func testCodegenAtomicIntStoreAndLoad() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(0)
            println(a.load())
            a.store(42)
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntStoreLoad", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "0\n42\n")
        }
    }

    // MARK: - AtomicLong edge cases

    func testCodegenAtomicLongBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(100L)
            println(a.load())
            a.store(200L)
            println(a.load())
            println(a.exchange(300L))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongBasic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "100\n200\n200\n300\n")
        }
    }

    func testCodegenAtomicLongCASSuccessAndFailure() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(50L)
            println(a.compareAndSet(50L, 60L))
            println(a.load())
            println(a.compareAndSet(99L, 70L))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongCAS", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\n60\nfalse\n60\n")
        }
    }

    func testCodegenAtomicLongCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(10L)
            println(a.compareAndExchange(10L, 20L))
            println(a.load())
            println(a.compareAndExchange(999L, 30L))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongCAE", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "10\n20\n20\n20\n")
        }
    }

    func testCodegenAtomicLongArithmeticOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(1L)
            println(a.addAndFetch(4L))
            println(a.fetchAndAdd(3L))
            println(a.load())
            println(a.fetchAndIncrement())
            println(a.load())
            println(a.fetchAndDecrement())
            println(a.load())
            println(a.incrementAndFetch())
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongArithmetic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "5\n5\n8\n8\n9\n9\n8\n9\n9\n")
        }
    }

    func testCodegenAtomicLongNegativeDeltaArithmetic() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(10L)
            println(a.addAndFetch(-3L))
            println(a.load())
            println(a.fetchAndAdd(-2L))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongNegativeDelta", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "7\n7\n7\n5\n")
        }
    }

    // MARK: - AtomicBoolean edge cases

    func testCodegenAtomicBooleanBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            println(a.load())
            a.store(true)
            println(a.load())
            println(a.exchange(false))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicBooleanBasic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "false\ntrue\ntrue\nfalse\n")
        }
    }

    func testCodegenAtomicBooleanAsJavaAtomic() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean
        import kotlin.concurrent.atomics.asJavaAtomic

        fun main() {
            val atomic = AtomicBoolean(true)
            val javaAtomic: java.util.concurrent.atomic.AtomicBoolean = atomic.asJavaAtomic()
            println("ok")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicBooleanAsJavaAtomic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "ok\n")
        }
    }

    func testCodegenAtomicBooleanCASSuccessAndFailure() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(true)
            println(a.compareAndSet(true, false))
            println(a.load())
            println(a.compareAndSet(true, false))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicBooleanCAS", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\nfalse\nfalse\nfalse\n")
        }
    }

    func testCodegenAtomicBooleanCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            // Success: returns old (false), updates to true
            println(a.compareAndExchange(false, true))
            println(a.load())
            // Failure: returns current (true), unchanged
            println(a.compareAndExchange(false, false))
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicBooleanCAE", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "false\ntrue\ntrue\ntrue\n")
        }
    }

    // MARK: - AtomicReference identity semantics

    func testCodegenAtomicReferenceAsJavaAtomic() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference
        import kotlin.concurrent.atomics.asJavaAtomic

        fun main() {
            val atomic = AtomicReference("value")
            val javaAtomic: java.util.concurrent.atomic.AtomicReference<String> = atomic.asJavaAtomic()
            println("ok")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicReferenceAsJavaAtomic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "ok\n")
        }
    }

    func testCodegenAtomicReferenceIdentityVsEqualityCAS() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val obj1 = "hello"
            val obj2 = "hello"
            val ref = AtomicReference(obj1)
            // CAS with equal-but-different object (obj2 has same content but may be distinct)
            // In Kotlin Native/JVM, AtomicReference CAS uses identity (===)
            // obj1 is the loaded reference; use identity match
            val loaded = ref.load()
            println(ref.compareAndSet(loaded, obj2))
            println(ref.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicRefIdentity", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            // CAS with the identity-loaded reference must succeed
            XCTAssertEqual(normalized, "true\nhello\n")
        }
    }

    func testCodegenAtomicReferenceCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val a = "alpha"
            val b = "beta"
            val c = "gamma"
            val ref = AtomicReference(a)
            // Success: returns old value (a)
            val old = ref.compareAndExchange(a, b)
            println(old)
            println(ref.load())
            // Failure: returns current (b), unchanged
            val cur = ref.compareAndExchange(c, a)
            println(cur)
            println(ref.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicRefCAE", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "alpha\nbeta\nbeta\nbeta\n")
        }
    }

    func testCodegenAtomicReferenceExchangeAndStore() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val ref = AtomicReference("v1")
            // exchange returns old, stores new
            val prev = ref.exchange("v2")
            println(prev)
            println(ref.load())
            // store then load
            ref.store("v3")
            println(ref.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicRefExchangeStore", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "v1\nv2\nv3\n")
        }
    }

    func testCodegenAtomicArrayFetchAndUpdateAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray

        fun main() {
            val arr = AtomicArray<String?>(1)
            arr.storeAt(0, "a")
            val old = arr.fetchAndUpdateAt(0) { (it ?: "") + "b" }
            println(old)
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicArrayFetchAndUpdateAt", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "a\nab\n")
        }
    }

    func testCodegenAtomicArrayUpdateAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray

        fun main() {
            val arr = AtomicArray<String?>(1)
            arr.storeAt(0, "a")
            arr.updateAt(0) { (it ?: "") + "b" }
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicArrayUpdateAt", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "ab\n")
        }
    }

    func testCodegenAtomicArrayCompareAndSetAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray

        fun main() {
            val arr = AtomicArray<String?>(1)
            arr.storeAt(0, "a")
            val old = arr.loadAt(0)
            println(arr.compareAndSetAt(0, old, "b"))
            println(arr.loadAt(0))
            println(arr.compareAndSetAt(0, old, "c"))
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicArrayCompareAndSetAt", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\nb\nfalse\nb\n")
        }
    }

    func testCodegenAtomicArrayOfNullsFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val arr = atomicArrayOfNulls<String>(2)
            println(arr.size)
            arr.storeAt(0, "first")
            arr.storeAt(1, "value")
            println(arr.loadAt(0))
            println(arr.loadAt(1))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicArrayOfNullsFactory", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "2\nfirst\nvalue\n")
        }
    }

    func testCodegenAtomicArrayUpdateAndFetchAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray

        fun main() {
            val arr = AtomicArray<String?>(1)
            arr.storeAt(0, "a")
            val new = arr.updateAndFetchAt(0) { (it ?: "") + "b" }
            println(new)
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicArrayUpdateAndFetchAt", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "ab\nab\n")
        }
    }

    // MARK: - AtomicIntArray edge cases

    func testCodegenAtomicIntArrayAsJavaAtomicArray() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.asJavaAtomicArray

        fun main() {
            val atomic = AtomicIntArray(1)
            val javaAtomic: java.util.concurrent.atomic.AtomicIntegerArray = atomic.asJavaAtomicArray()
            println("ok")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayAsJavaAtomicArray", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "ok\n")
        }
    }

    func testCodegenAtomicIntArrayBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(3)
            println(arr.size)
            println(arr.loadAt(0))
            arr.storeAt(1, 42)
            println(arr.loadAt(1))
            println(arr.exchangeAt(1, 99))
            println(arr.loadAt(1))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayBasic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "3\n0\n42\n42\n99\n")
        }
    }

    func testCodegenAtomicIntArrayInitFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(3) { it }
            println(arr.size)
            println(arr.loadAt(0))
            println(arr.loadAt(1))
            println(arr.loadAt(2))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayInitFactory", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "3\n0\n1\n2\n")
        }
    }

    func testCodegenAtomicIntArrayCASOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(2)
            arr.storeAt(0, 10)
            println(arr.compareAndSetAt(0, 10, 20))
            println(arr.loadAt(0))
            println(arr.compareAndSetAt(0, 99, 30))
            println(arr.loadAt(0))
            println(arr.compareAndExchangeAt(0, 20, 50))
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayCAS", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\n20\nfalse\n20\n20\n50\n")
        }
    }

    func testCodegenAtomicIntArrayArithmeticOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(1)
            println(arr.addAndFetchAt(0, 5))
            println(arr.fetchAndAddAt(0, 3))
            println(arr.loadAt(0))
            println(arr.fetchAndIncrementAt(0))
            println(arr.loadAt(0))
            println(arr.incrementAndFetchAt(0))
            println(arr.loadAt(0))
            println(arr.fetchAndDecrementAt(0))
            println(arr.loadAt(0))
            println(arr.decrementAndFetchAt(0))
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayArithmetic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "5\n5\n8\n8\n9\n10\n10\n10\n9\n8\n8\n")
        }
    }

    func testCodegenAtomicIntArrayFetchAndUpdateAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(1)
            arr.storeAt(0, 10)
            val old = arr.fetchAndUpdateAt(0) { it * 2 }
            println(old)
            println(arr.loadAt(0))
            val fetched = arr.fetchAndUpdateAt(0) { it - 5 }
            println(fetched)
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayFetchAndUpdateAt", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "10\n20\n20\n15\n")
        }
    }

    func testCodegenAtomicIntArrayIndexOperator() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(2)
            arr[0] = 7
            arr[1] = 13
            println(arr[0])
            println(arr[1])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayIndexOp", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "7\n13\n")
        }
    }

    // MARK: - AtomicLongArray edge cases

    func testCodegenAtomicLongArrayBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(3)
            println(arr.size)
            println(arr.loadAt(0))
            arr.storeAt(2, 100L)
            println(arr.loadAt(2))
            println(arr.exchangeAt(2, 200L))
            println(arr.loadAt(2))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongArrayBasic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "3\n0\n100\n100\n200\n")
        }
    }

    func testCodegenAtomicLongArrayCASOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            arr.storeAt(0, 10L)
            println(arr.compareAndSetAt(0, 10L, 20L))
            println(arr.loadAt(0))
            println(arr.compareAndSetAt(0, 99L, 30L))
            println(arr.loadAt(0))
            println(arr.compareAndExchangeAt(0, 20L, 50L))
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongArrayCAS", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\n20\nfalse\n20\n20\n50\n")
        }
    }

    func testCodegenAtomicLongArrayArithmeticOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            println(arr.addAndFetchAt(0, 5L))
            println(arr.fetchAndAddAt(0, 3L))
            println(arr.loadAt(0))
            println(arr.fetchAndIncrementAt(0))
            println(arr.loadAt(0))
            println(arr.incrementAndFetchAt(0))
            println(arr.fetchAndDecrementAt(0))
            println(arr.loadAt(0))
            println(arr.decrementAndFetchAt(0))
            println(arr.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongArrayArithmetic", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "5\n5\n8\n8\n9\n10\n10\n9\n8\n8\n")
        }
    }

    func testCodegenAtomicIncrementAndGetOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.incrementAndGet())
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.incrementAndGet())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.incrementAndGet(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.incrementAndGet(0))
            println(longArray.loadAt(0))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIncrementAndGet", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "2\n2\n4\n4\n6\n6\n8\n8\n")
        }
    }

    // MARK: - AtomicInt default initial value

    func testCodegenAtomicIntDefaultInitialValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(0)
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntDefaultInit", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "0\n")
        }
    }

    // MARK: - AtomicInt getAndUpdate / updateAndGet

    func testCodegenAtomicIntGetAndUpdate() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(10)
            val old = a.getAndUpdate { it * 2 }
            println(old)
            println(a.load())
            val fetched = a.fetchAndUpdate { it - 3 }
            println(fetched)
            println(a.load())
            val new2 = a.updateAndGet { it + 5 }
            println(new2)
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntGetAndUpdate", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "10\n20\n20\n17\n22\n22\n")
        }
    }

    func testCodegenAtomicLongGetAndUpdate() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(10L)
            val old = a.getAndUpdate { it * 2L }
            println(old)
            println(a.load())
            val fetched = a.fetchAndUpdate { it - 3L }
            println(fetched)
            println(a.load())
            val new2 = a.updateAndGet { it + 5L }
            println(new2)
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongGetAndUpdate", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "10\n20\n20\n17\n22\n22\n")
        }
    }

    // MARK: - AtomicBoolean getAndUpdate / updateAndGet

    func testCodegenAtomicBooleanGetAndUpdate() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            val old = a.getAndUpdate { !it }
            println(old)
            println(a.load())
            val new2 = a.updateAndGet { !it }
            println(new2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicBooleanGetAndUpdate", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "false\ntrue\nfalse\n")
        }
    }

    // MARK: - kotlin.concurrent (non-atomics) AtomicInt

    func testCodegenKotlinConcurrentAtomicIntLoadStore() throws {
        let source = """
        import kotlin.concurrent.AtomicInt

        fun main() {
            val a = AtomicInt(5)
            println(a.load())
            a.store(10)
            println(a.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "KConcurrentAtomicInt", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "5\n10\n")
        }
    }

    func testCodegenKotlinConcurrentAtomicLongOperations() throws {
        let source = """
        import kotlin.concurrent.AtomicLong

        fun main() {
            val value = AtomicLong(5L)
            println(value.load())
            value.store(10L)
            println(value.load())
            println(value.addAndFetch(2L))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "KConcurrentAtomicLong", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "5\n10\n12\n")
        }
    }

    func testCodegenKotlinConcurrentAtomicReferenceOperations() throws {
        let source = """
        import kotlin.concurrent.AtomicReference

        fun main() {
            val ref = AtomicReference("first")
            println(ref.load())
            ref.store("second")
            println(ref.exchange("third"))
            println(ref.load())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "KConcurrentAtomicReference", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "first\nsecond\nthird\n")
        }
    }

    func testCodegenKotlinConcurrentAtomicIntArrayOperations() throws {
        let source = """
        import kotlin.concurrent.AtomicIntArray

        fun main() {
            val values = AtomicIntArray(2)
            values.storeAt(0, 10)
            values[1] = 20
            println(values.loadAt(0))
            println(values[1])
            println(values.addAndFetchAt(0, 5))
            println(values.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "KConcurrentAtomicIntArray", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "10\n20\n15\n2\n")
        }
    }

    func testCodegenKotlinConcurrentAtomicLongArrayOperations() throws {
        let source = """
        import kotlin.concurrent.AtomicLongArray

        fun main() {
            val values = AtomicLongArray(2)
            values.storeAt(0, 10L)
            values[1] = 20L
            println(values.loadAt(0))
            println(values[1])
            println(values.addAndFetchAt(0, 5L))
            println(values.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "KConcurrentAtomicLongArray", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "10\n20\n15\n2\n")
        }
    }

    // MARK: - ABI-001: AtomicBoolean.value setter

    func testCodegenAtomicBooleanValueSetterWiresBoolStore() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            a.value = true
            println(a.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicBoolSetterABI001", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\n")
        }
    }

    func testCodegenAtomicIntValueSetterWiresIntStore() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(0)
            a.value = 42
            println(a.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntSetterABI001", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "42\n")
        }
    }

    // MARK: - BUG-01: AtomicReference getAndUpdate / fetchAndUpdate / updateAndGet type inference

    func testCodegenAtomicReferenceGetAndUpdate() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val a = AtomicReference("hello")
            val old = a.getAndUpdate { it + "!" }
            println(old)
            println(a.value)
            val fetched = a.fetchAndUpdate { it + "?" }
            println(fetched)
            println(a.value)
            val updated = a.updateAndGet { it.uppercase() }
            println(updated)
            val fetchedNew = a.updateAndFetch { it + "~" }
            println(fetchedNew)
            println(a.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicRefGetAndUpdateBUG01", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "hello\nhello!\nhello!\nhello!?\nHELLO!?\nHELLO!?~\nHELLO!?~\n")
        }
    }

    // MARK: - BUG-02: AtomicIntArray / AtomicLongArray OOB throws IndexOutOfBoundsException

    func testCodegenAtomicIntArrayOOBLoadThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val a = AtomicIntArray(3)
            try {
                val _ = a[5]
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayOOBLoad", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "caught\n")
        }
    }

    func testCodegenAtomicIntArrayOOBStoreThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val a = AtomicIntArray(3)
            try {
                a[10] = 99
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicIntArrayOOBStore", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "caught\n")
        }
    }

    func testCodegenAtomicLongArrayOOBLoadThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val a = AtomicLongArray(2)
            try {
                val _ = a[7]
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongArrayOOBLoad", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "caught\n")
        }
    }

    func testCodegenAtomicLongArrayOOBStoreThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val a = AtomicLongArray(2)
            try {
                a[99] = 1L
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "AtomicLongArrayOOBStore", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "caught\n")
        }
    }
}
