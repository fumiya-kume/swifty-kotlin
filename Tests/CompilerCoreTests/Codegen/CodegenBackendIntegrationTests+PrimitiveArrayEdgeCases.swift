@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-004: Primitive array edge case coverage
// Covers IntArray/LongArray/ShortArray/ByteArray/CharArray/DoubleArray/FloatArray/BooleanArray
// and unsigned variants, exercising zero-init constructor, fill, copyOf, contentEquals,
// toList round-trip, asList view semantics, and size-zero semantics — distinct from
// generic-array coverage in #1185.
extension CodegenBackendIntegrationTests {

    // MARK: - Zero-initialized constructor (IntArray(n) without lambda)

    func testPrimitiveArrayZeroInit() throws {
        let source = """
        fun main() {
            val ia = IntArray(4)
            println(ia.size)
            println(ia[0])
            println(ia[3])

            val la = LongArray(2)
            println(la.size)
            println(la[0])

            val ba = BooleanArray(3)
            println(ba.size)
            println(ba[0])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveArrayZeroInit",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "4\n0\n0\n2\n0\n3\nfalse\n")
        }
    }

    // MARK: - Size-zero primitive arrays

    func testPrimitiveArraySizeZero() throws {
        let source = """
        fun main() {
            val empty = IntArray(0)
            println(empty.size)

            val emptyLong = LongArray(0)
            println(emptyLong.size)

            val emptyBool = BooleanArray(0)
            println(emptyBool.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveArraySizeZero",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "0\n0\n0\n")
        }
    }

    // MARK: - Factory with init lambda vs zero-init

    func testPrimitiveArrayFactoryVsZeroInit() throws {
        let source = """
        fun main() {
            // init lambda: each element is index * 2
            val withLambda = IntArray(5) { it * 2 }
            println(withLambda[0])
            println(withLambda[2])
            println(withLambda[4])

            // zero-init: all elements are 0
            val zeroInit = IntArray(5)
            println(zeroInit[0])
            println(zeroInit[4])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveArrayFactoryVsZeroInit",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "0\n4\n8\n0\n0\n")
        }
    }

    // MARK: - Multiple primitive type creation (Short, Byte, Double, Float)

    func testPrimitiveArrayMultipleTypes() throws {
        let source = """
        fun main() {
            val shorts = shortArrayOf(10, 20, 30)
            println(shorts.size)
            println(shorts[1])

            val bytes = byteArrayOf(1, 2, 3)
            println(bytes.size)
            println(bytes[0])

            val doubles = doubleArrayOf(1.5, 2.5)
            println(doubles.size)
            println(doubles[0])

            val floats = floatArrayOf(3.0f, 4.0f)
            println(floats.size)
            println(floats[1])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveArrayMultipleTypes",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n20\n3\n1\n2\n1.5\n2\n4.0\n")
        }
    }

    // MARK: - UIntArray factory and element access

    func testUIntArrayFactoryAndAccess() throws {
        let source = """
        fun main() {
            val uints = uintArrayOf(1u, 2u, 3u)
            println(uints.size)
            println(uints[0])
            println(uints[2])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UIntArrayFactoryAndAccess",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n1\n3\n")
        }
    }

    func testUnsignedPrimitiveArrayCopyOfRange() throws {
        let source = """
        fun main() {
            println(ubyteArrayOf(1.toUByte(), 2.toUByte(), 3.toUByte()).copyOfRange(1, 3).toList())
            println(ushortArrayOf(10.toUShort(), 20.toUShort(), 30.toUShort()).copyOfRange(0, 2).toList())
            println(uintArrayOf(100u, 200u, 300u).copyOfRange(1, 3).toList())
            println(ulongArrayOf(1000uL, 2000uL, 3000uL).copyOfRange(0, 1).toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedPrimitiveArrayCopyOfRange",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [2, 3]
                [10, 20]
                [200, 300]
                [1000]
                """
                + "\n"
            )
        }
    }

    func testSignedArrayViewConversionsFromUnsignedArrays() throws {
        let source = """
        fun main() {
            val ubytes = ubyteArrayOf(1.toUByte(), 2.toUByte(), 3.toUByte())
            val bytes = ubytes.asByteArray()
            ubytes[1] = 9.toUByte()
            println(bytes.toList())

            val ushorts = ushortArrayOf(10.toUShort(), 20.toUShort())
            println(ushorts.asShortArray().toList())

            val uints = uintArrayOf(100u, 200u)
            println(uints.asIntArray().toList())

            val ulongs = ulongArrayOf(1000uL, 2000uL)
            println(ulongs.asLongArray().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SignedArrayViewConversionsFromUnsignedArrays",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 9, 3]
                [10, 20]
                [100, 200]
                [1000, 2000]
                """
                + "\n"
            )
        }
    }

    func testUnsignedCollectionToPrimitiveArrayConversions() throws {
        let source = """
        fun main() {
            val ubytes = listOf(1.toUByte(), 255.toUByte()).toUByteArray()
            println(ubytes.size)
            println(ubytes[0])
            println(ubytes[1])

            val ushorts = listOf(1.toUShort(), 65535.toUShort()).toUShortArray()
            println(ushorts.size)
            println(ushorts[1])

            val uints = listOf(1u, 4000000000u).toUIntArray()
            println(uints.size)
            println(uints[1])

            val ulongs = listOf(1uL, 4000000000uL).toULongArray()
            println(ulongs.size)
            println(ulongs[1])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedCollectionToPrimitiveArrayConversions",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "2\n1\n255\n2\n65535\n2\n4000000000\n2\n4000000000\n")
        }
    }

    // MARK: - fill on primitive array

    func testPrimitiveArrayFill() throws {
        let source = """
        fun main() {
            val arr = IntArray(4)
            println(arr[0])
            arr.fill(7)
            println(arr[0])
            println(arr[3])

            val bools = BooleanArray(3)
            println(bools[0])
            bools.fill(true)
            println(bools[0])
            println(bools[2])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveArrayFill",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "0\n7\n7\nfalse\ntrue\ntrue\n")
        }
    }

    // MARK: - copyOf on primitive array (element access on copy)

    func testPrimitiveArrayCopyOf() throws {
        let source = """
        fun main() {
            val original = intArrayOf(1, 2, 3)
            val copy = original.copyOf()
            println(copy[0])
            println(copy[2])

            // Verify copy independence: modifying copy does not affect original
            copy[0] = 99
            println(original[0])
            println(copy[0])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveArrayCopyOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "1\n3\n1\n99\n")
        }
    }

    // MARK: - contentEquals on generic Array<Int> (primitive arrays use Array<T> box)

    func testBoxedIntArrayContentEquals() throws {
        let source = """
        fun main() {
            val a = arrayOf(1, 2, 3)
            val b = arrayOf(1, 2, 3)
            val c = arrayOf(1, 2, 4)
            println(a.contentEquals(b))
            println(a.contentEquals(c))

            val empty1 = emptyArray<Int>()
            val empty2 = emptyArray<Int>()
            println(empty1.contentEquals(empty2))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BoxedIntArrayContentEquals",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "true\nfalse\ntrue\n")
        }
    }

    // MARK: - toList round-trip for primitive arrays

    func testPrimitiveArrayToListRoundTrip() throws {
        let source = """
        fun main() {
            val ints = intArrayOf(10, 20, 30)
            val list = ints.toList()
            println(list.size)
            println(list[0])
            println(list[2])

            val longs = longArrayOf(100L, 200L)
            val longList = longs.toList()
            println(longList.size)
            println(longList[1])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveArrayToListRoundTrip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n10\n30\n2\n200\n")
        }
    }

    // MARK: - asList view for unsigned primitive arrays

    func testUnsignedPrimitiveArrayAsListViewReflectsMutations() throws {
        let source = """
        fun main() {
            val uints = uintArrayOf(100u, 200u, 300u)
            val uintView = uints.asList()
            println(uintView.size)
            println(uintView[1])
            uints[1] = 900u
            println(uintView[1])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedPrimitiveArrayAsListView",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n200\n900\n")
        }
    }

    func testUnsignedPrimitiveArrayToTypedArrayReturnsGenericArrays() throws {
        let source = """
        fun main() {
            val ubytes = ubyteArrayOf()
            val ubyteTyped = ubytes.toTypedArray()

            val ushorts = ushortArrayOf()
            val ushortTyped = ushorts.toTypedArray()

            val uints = uintArrayOf(100u, 200u)
            val uintTyped = uints.toTypedArray()
            println(uintTyped[1])
            uintTyped[1] = 900u
            println(uints[1])
            println(uintTyped[1])

            val ulongs = ulongArrayOf(1000uL, 2000uL)
            val ulongTyped = ulongs.toTypedArray()
            println(ulongTyped[0])
            ulongTyped[0] = 9000uL
            println(ulongs[0])
            println(ulongTyped[0])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedPrimitiveArrayToTypedArray",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "200\n200\n900\n1000\n1000\n9000\n")
        }
    }

    // MARK: - copyOf(newSize, init) for unsigned primitive arrays

    func testUnsignedPrimitiveArrayCopyOfNewSizeAndInit() throws {
        let source = """
        fun main() {
            val ubytes = ubyteArrayOf()
            val ubyteGrow = ubytes.copyOf(2)
            println(ubyteGrow.size)

            val ushorts = ushortArrayOf()
            val ushortGrow = ushorts.copyOf(1)
            println(ushortGrow.size)

            val uints = uintArrayOf(10u, 20u)
            val uintGrow = uints.copyOf(4) { 700u }
            println(uintGrow.size)
            println(uintGrow[0])
            println(uintGrow[1])
            println(uintGrow[2])
            println(uintGrow[3])
            uintGrow[0] = 99u
            println(uints[0])

            val uintShrink = uints.copyOf(1)
            println(uintShrink.size)
            println(uintShrink[0])

            val ulongs = ulongArrayOf(100uL)
            val ulongGrow = ulongs.copyOf(3) { 9000uL }
            println(ulongGrow[0])
            println(ulongGrow[1])
            println(ulongGrow[2])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedPrimitiveArrayCopyOfNewSizeAndInit",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "2\n1\n4\n10\n20\n700\n700\n10\n1\n10\n100\n9000\n9000\n")
        }
    }

    // MARK: - toIntArray from List round-trip

    func testListToIntArrayRoundTrip() throws {
        let source = """
        fun main() {
            val list = listOf(5, 10, 15)
            val arr = list.toIntArray()
            println(arr.size)
            println(arr[0])
            println(arr[2])

            // Modify array; list should be unaffected
            arr[0] = 99
            println(list[0])
            println(arr[0])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListToIntArrayRoundTrip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n5\n15\n5\n99\n")
        }
    }

    // MARK: - contentHashCode stability for boxed int arrays

    func testBoxedIntArrayContentHashCode() throws {
        let source = """
        fun main() {
            val a = arrayOf(1, 2, 3)
            val b = arrayOf(1, 2, 3)
            val c = arrayOf(1, 2, 4)
            // Same content → same hash
            println(a.contentHashCode() == b.contentHashCode())
            // Different content → different hash (standard Kotlin polynomial hash)
            println(a.contentHashCode() == c.contentHashCode())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BoxedIntArrayContentHashCode",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "true\nfalse\n")
        }
    }
}
