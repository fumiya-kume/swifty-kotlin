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

    func testArrayReversedArrayOverloads() throws {
        let source = """
        fun main() {
            println(arrayOf("a", "b", "c").reversedArray().toList())
            println(intArrayOf(1, 2, 3, 4).reversedArray().toList())
            println(uintArrayOf(10u, 20u, 30u).reversedArray().toList())
            println(booleanArrayOf(true, false, false).reversedArray().toList())
            println(emptyArray<String>().reversedArray().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayReversedArrayOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [c, b, a]
                [4, 3, 2, 1]
                [30, 20, 10]
                [0, 0, 1]
                []
                """
                + "\n"
            )
        }
    }

    func testArraySortedArrayOverloads() throws {
        let source = """
        fun main() {
            println(arrayOf("c", "a", "b").sortedArray().toList())
            println(intArrayOf(4, 1, 3, 2).sortedArray().toList())
            println(uintArrayOf(30u, 10u, 20u).sortedArray().toList())
            println(booleanArrayOf(true, false, false).sortedArray().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArraySortedArrayOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [a, b, c]
                [1, 2, 3, 4]
                [10, 20, 30]
                [0, 0, 1]
                """
                + "\n"
            )
        }
    }

    func testArraySortedArrayDescendingOverloads() throws {
        let source = """
        fun main() {
            println(arrayOf("c", "a", "b").sortedArrayDescending().toList())
            println(intArrayOf(4, 1, 3, 2).sortedArrayDescending().toList())
            println(uintArrayOf(30u, 10u, 20u).sortedArrayDescending().toList())
            println(booleanArrayOf(true, false, false).sortedArrayDescending().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArraySortedArrayDescendingOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [c, b, a]
                [4, 3, 2, 1]
                [30, 20, 10]
                [1, 0, 0]
                """
                + "\n"
            )
        }
    }

    func testArrayCopyIntoOverloads() throws {
        let source = """
        fun main() {
            val words = arrayOf("a", "b", "c", "d")
            val wordDestination = arrayOf("x", "y", "z", "w", "q")
            words.copyInto(wordDestination, destinationOffset = 1, startIndex = 1, endIndex = 3)
            println(wordDestination.toList())

            val defaultDestination = arrayOf(0, 0, 0)
            arrayOf(1, 2, 3).copyInto(defaultDestination)
            println(defaultDestination.toList())

            val intDestination = intArrayOf(9, 9, 9, 9, 9)
            intArrayOf(1, 2, 3, 4).copyInto(intDestination, destinationOffset = 2, startIndex = 1, endIndex = 4)
            println(intDestination.toList())

            val uintDestination = uintArrayOf(0u, 0u, 0u)
            uintArrayOf(10u, 20u, 30u).copyInto(uintDestination)
            println(uintDestination.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayCopyIntoOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [x, b, c, w, q]
                [1, 2, 3]
                [9, 9, 2, 3, 4]
                [10, 20, 30]
                """
                + "\n"
            )
        }
    }

    func testArraySliceArrayOverloads() throws {
        let source = """
        fun main() {
            val words = arrayOf("a", "b", "c", "d")
            println(words.sliceArray(1..2).toList())
            println(words.sliceArray(listOf(3, 0)).toList())
            println(intArrayOf(1, 2, 3, 4).sliceArray(1..3).toList())
            println(uintArrayOf(10u, 20u, 30u).sliceArray(listOf(2, 0)).toList())
            println(booleanArrayOf(true, false, false).sliceArray(0..1).toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArraySliceArrayOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [b, c]
                [d, a]
                [2, 3, 4]
                [30, 10]
                [1, 0]
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

    func testUnsignedArrayViewConversions() throws {
        let source = """
        fun main() {
            val bytes = byteArrayOf(1, 2, 3)
            val ubytes = bytes.asUByteArray()
            bytes[1] = 9
            println(ubytes.toList())

            val shorts = shortArrayOf(10, 20)
            println(shorts.asUShortArray().toList())

            val ints = intArrayOf(100, 200)
            println(ints.asUIntArray().toList())

            val longs = longArrayOf(1000L, 2000L)
            println(longs.asULongArray().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedArrayViewConversions",
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

    func testUnsignedPrimitiveArrayCopyOfRangeReturnsUnsignedArrays() throws {
        let source = """
        fun main() {
            val ubytes = ubyteArrayOf()
            val ubyteCopy = ubytes.copyOfRange(0, 0)
            println(ubyteCopy.size)

            val ushorts = ushortArrayOf()
            val ushortCopy = ushorts.copyOfRange(0, 0)
            println(ushortCopy.size)

            val uints = uintArrayOf(100u, 200u, 300u)
            val uintCopy = uints.copyOfRange(1, 3)
            println(uintCopy.size)
            println(uintCopy[0])
            uintCopy[0] = 900u
            println(uints[1])
            println(uintCopy[0])

            val ulongs = ulongArrayOf(1000uL, 2000uL, 3000uL)
            val ulongCopy = ulongs.copyOfRange(0, 2)
            println(ulongCopy.size)
            println(ulongCopy[1])
            ulongCopy[1] = 9000uL
            println(ulongs[1])
            println(ulongCopy[1])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedPrimitiveArrayCopyOfRangeReturnsUnsignedArrays",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "0\n0\n2\n200\n200\n900\n2\n2000\n2000\n9000\n")
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

    func testListToBooleanArrayRoundTrip() throws {
        let source = """
        fun main() {
            val list = listOf(true, false, true)
            val arr = list.toBooleanArray()
            println(arr.size)
            println(if (arr[0]) "T" else "F")
            println(if (arr[1]) "T" else "F")

            arr[1] = true
            println(if (list[1]) "T" else "F")
            println(if (arr[1]) "T" else "F")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListToBooleanArrayRoundTrip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\nT\nF\nF\nT\n")
        }
    }

    func testListToShortArrayRoundTrip() throws {
        let source = """
        fun main() {
            val list = listOf(1.toShort(), (-2).toShort(), 32767.toShort())
            val arr = list.toShortArray()
            println(arr.size)
            println(arr[0])
            println(arr[1])
            println(arr[2])

            arr[0] = 7.toShort()
            println(list[0])
            println(arr[0])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListToShortArrayRoundTrip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n1\n-2\n32767\n1\n7\n")
        }
    }

    func testListToDoubleArrayRoundTrip() throws {
        let source = """
        fun main() {
            val list = listOf(1.5, -2.25, 0.5)
            val arr = list.toDoubleArray()
            println(arr.size)
            println(arr[0])
            println(arr[1])
            println(arr[2])

            arr[0] = 9.25
            println(list[0])
            println(arr[0])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListToDoubleArrayRoundTrip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n1.5\n-2.25\n0.5\n1.5\n9.25\n")
        }
    }

    func testListToFloatArrayRoundTrip() throws {
        let source = """
        fun main() {
            val list = listOf(1.5f, -2.25f, 0.5f)
            val arr = list.toFloatArray()
            println(arr.size)
            println(arr[0])
            println(arr[1])
            println(arr[2])

            arr[0] = 9.25f
            println(list[0])
            println(arr[0])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListToFloatArrayRoundTrip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "3\n1.5\n-2.25\n0.5\n1.5\n9.25\n")
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

    func testArrayContentDeepToString() throws {
        let source = """
        fun main() {
            val nested = arrayOf(arrayOf(1, 2), arrayOf("x", "y"), intArrayOf(3, 4))
            println(nested.contentDeepToString())

            val self = arrayOfNulls<Any>(1)
            self[0] = self
            println(self.contentDeepToString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayContentDeepToString",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "[[1, 2], [x, y], [3, 4]]\n[[...]]\n")
        }
    }

    // MARK: - contentToString for boxed and primitive arrays

    func testArrayContentToStringOverloads() throws {
        let source = """
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            val boxed = arrayOf<Any>(1, "two", 3)
            println(boxed.contentToString())
            println(intArrayOf(1, -2, 3).contentToString())
            println(byteArrayOf(1, (-1).toByte()).contentToString())
            println(shortArrayOf(2, (-3).toShort()).contentToString())
            println(longArrayOf(1L, 4000000000L).contentToString())
            println(floatArrayOf(1.5f, -2.0f).contentToString())
            println(doubleArrayOf(2.25, -0.5).contentToString())
            println(booleanArrayOf(true, false).contentToString())
            println(charArrayOf('a', 'Z').contentToString())
            println(ubyteArrayOf(1.toUByte(), 255.toUByte()).contentToString())
            println(ushortArrayOf(1.toUShort(), 65535.toUShort()).contentToString())
            println(uintArrayOf(1u, 4000000000u).contentToString())
            println(ulongArrayOf(1uL, 4000000000uL).contentToString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayContentToStringOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [1, two, 3]
                [1, -2, 3]
                [1, -1]
                [2, -3]
                [1, 4000000000]
                [1.5, -2.0]
                [2.25, -0.5]
                [true, false]
                [a, Z]
                [1, 255]
                [1, 65535]
                [1, 4000000000]
                [1, 4000000000]
                """
                + "\n"
            )
        }
    }

    func testArrayContentDeepHashCode() throws {
        let source = """
        fun main() {
            val left = arrayOf(arrayOf(1, 2), arrayOf("x"))
            val same = arrayOf(arrayOf(1, 2), arrayOf("x"))
            val differentNested = arrayOf(arrayOf(1, 3), arrayOf("x"))
            val shallowSameShape = arrayOf(arrayOf(1, 2), arrayOf("x"))

            println(left.contentDeepHashCode() == same.contentDeepHashCode())
            println(left.contentDeepHashCode() == differentNested.contentDeepHashCode())
            println(left.contentHashCode() == shallowSameShape.contentHashCode())

            val primitiveLeft = arrayOf(intArrayOf(1, 2), booleanArrayOf(true, false))
            val primitiveSame = arrayOf(intArrayOf(1, 2), booleanArrayOf(true, false))
            val primitiveDifferent = arrayOf(intArrayOf(1, 2), booleanArrayOf(false, true))
            println(primitiveLeft.contentDeepHashCode() == primitiveSame.contentDeepHashCode())
            println(primitiveLeft.contentDeepHashCode() == primitiveDifferent.contentDeepHashCode())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayContentDeepHashCode",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "true\nfalse\nfalse\ntrue\nfalse\n")
        }
    }

    func testArrayContentDeepEquals() throws {
        let source = """
        fun main() {
            val left = arrayOf(arrayOf(1, 2), arrayOf("x"))
            val same = arrayOf(arrayOf(1, 2), arrayOf("x"))
            val differentNested = arrayOf(arrayOf(1, 3), arrayOf("x"))
            val shallowSameShape = arrayOf(arrayOf(1, 2), arrayOf("x"))

            println(left.contentDeepEquals(same))
            println(left.contentDeepEquals(differentNested))
            println(left.contentEquals(shallowSameShape))

            val primitiveLeft = arrayOf(intArrayOf(1, 2), booleanArrayOf(true, false))
            val primitiveSame = arrayOf(intArrayOf(1, 2), booleanArrayOf(true, false))
            val primitiveDifferent = arrayOf(intArrayOf(1, 2), booleanArrayOf(false, true))
            println(primitiveLeft.contentDeepEquals(primitiveSame))
            println(primitiveLeft.contentDeepEquals(primitiveDifferent))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayContentDeepEquals",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "true\nfalse\nfalse\ntrue\nfalse\n")
        }
    }
}
