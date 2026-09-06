#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendPrimitiveArrayEdgeCasesTests {

    @Test
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
        try assertKotlinOutput(source, moduleName: "PrimitiveArrayZeroInit", expected: "4\n0\n0\n2\n0\n3\nfalse\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "PrimitiveArraySizeZero", expected: "0\n0\n0\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "PrimitiveArrayFactoryVsZeroInit", expected: "0\n4\n8\n0\n0\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "PrimitiveArrayMultipleTypes", expected: "3\n20\n3\n1\n2\n1.5\n2\n4.0\n")
    }

    @Test
    func testUIntArrayFactoryAndAccess() throws {
        let source = """
        fun main() {
            val uints = uintArrayOf(1u, 2u, 3u)
            println(uints.size)
            println(uints[0])
            println(uints[2])
        }
        """
        try assertKotlinOutput(source, moduleName: "UIntArrayFactoryAndAccess", expected: "3\n1\n3\n")
    }

    @Test
    func testUnsignedArraySizeToListCopyAndAsListView() throws {
        let source = """
        fun main() {
            val ubytes = ubyteArrayOf(1.toUByte(), 2.toUByte())
            val ubyteCopy = ubytes.toList()
            val ubyteView = ubytes.asList()
            ubytes[0] = 9.toUByte()
            println(ubytes.size)
            println(ubyteCopy)
            println(ubyteView)

            val ushorts = ushortArrayOf(3.toUShort(), 4.toUShort())
            val ushortCopy = ushorts.toList()
            val ushortView = ushorts.asList()
            ushorts[0] = 8.toUShort()
            println(ushorts.size)
            println(ushortCopy)
            println(ushortView)

            val uints = uintArrayOf(5u, 6u)
            val uintCopy = uints.toList()
            val uintView = uints.asList()
            uints[0] = 7u
            println(uints.size)
            println(uintCopy)
            println(uintView)

            val ulongs = ulongArrayOf(10uL, 11uL)
            val ulongCopy = ulongs.toList()
            val ulongView = ulongs.asList()
            ulongs[0] = 12uL
            println(ulongs.size)
            println(ulongCopy)
            println(ulongView)

            val objects = arrayOf("a", "b")
            val objectCopy: List<String> = objects.toList()
            objects[0] = "z"
            println(objects.size)
            println(objectCopy)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedArraySizeToListCopyAndAsListView",
            expected:
                """
                2
                [1, 2]
                [9, 2]
                2
                [3, 4]
                [8, 4]
                2
                [5, 6]
                [7, 6]
                2
                [10, 11]
                [12, 11]
                2
                [a, b]
                """
                + "\n"
        )
    }

    @Test
    func testUnsignedPrimitiveArrayCopyOfRange() throws {
        let source = """
        fun main() {
            println(ubyteArrayOf(1.toUByte(), 2.toUByte(), 3.toUByte()).copyOfRange(1, 3).toList())
            println(ushortArrayOf(10.toUShort(), 20.toUShort(), 30.toUShort()).copyOfRange(0, 2).toList())
            println(uintArrayOf(100u, 200u, 300u).copyOfRange(1, 3).toList())
            println(ulongArrayOf(1000uL, 2000uL, 3000uL).copyOfRange(0, 1).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UnsignedPrimitiveArrayCopyOfRange",
            expected:
                """
                [2, 3]
                [10, 20]
                [200, 300]
                [1000]
                """
                + "\n"
        )
    }

    @Test
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

        try assertKotlinOutput(
            source,
            moduleName: "ArrayReversedArrayOverloads",
            expected:
                """
                [c, b, a]
                [4, 3, 2, 1]
                [30, 20, 10]
                [false, false, true]
                []
                """
                + "\n"
        )
    }

    @Test
    func testArraySortedArrayOverloads() throws {
        let source = """
        fun main() {
            println(arrayOf("c", "a", "b").sortedArray().toList())
            println(intArrayOf(4, 1, 3, 2).sortedArray().toList())
            println(uintArrayOf(30u, 10u, 20u).sortedArray().toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArraySortedArrayOverloads",
            expected:
                """
                [a, b, c]
                [1, 2, 3, 4]
                [10, 20, 30]
                """
                + "\n"
        )
    }

    @Test
    func testArraySortedArrayDescendingOverloads() throws {
        let source = """
        fun main() {
            println(arrayOf("c", "a", "b").sortedArrayDescending().toList())
            println(intArrayOf(4, 1, 3, 2).sortedArrayDescending().toList())
            println(uintArrayOf(30u, 10u, 20u).sortedArrayDescending().toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArraySortedArrayDescendingOverloads",
            expected:
                """
                [c, b, a]
                [4, 3, 2, 1]
                [30, 20, 10]
                """
                + "\n"
        )
    }

    @Test
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

        try assertKotlinOutput(
            source,
            moduleName: "ArrayCopyIntoOverloads",
            expected:
                """
                [x, b, c, w, q]
                [1, 2, 3]
                [9, 9, 2, 3, 4]
                [10, 20, 30]
                """
                + "\n"
        )
    }

    @Test
    func testArrayCopyContractBoundariesAndOverlap() throws {
        let source = """
        fun main() {
            val values = arrayOf(1, 2, 3)
            println(values.copyOf(2).toList())
            println(values.copyOf(5).toList())
            println(values.copyOf(5) { index -> index * 10 }.toList())
            println(values.copyOfRange(1, 3).toList())

            val overlap = intArrayOf(1, 2, 3, 4)
            overlap.copyInto(overlap, destinationOffset = 1, startIndex = 0, endIndex = 3)
            println(overlap.toList())

            try {
                values.copyOf(-1)
                println("no-throw")
            } catch (e: Throwable) {
                println("copyOf-negative")
            }
            try {
                intArrayOf(1, 2).copyOf(-1)
                println("no-throw")
            } catch (e: Throwable) {
                println("primitive-copyOf-negative")
            }
            try {
                values.copyOfRange(2, 1)
                println("no-throw")
            } catch (e: Throwable) {
                println("copyOfRange-reversed")
            }
            try {
                values.copyInto(arrayOf(0, 0), destinationOffset = 0, startIndex = 0, endIndex = 3)
                println("no-throw")
            } catch (e: Throwable) {
                println("copyInto-destination-too-small")
            }
            try {
                values.copyInto(arrayOf(0, 0, 0), startIndex = -1)
                println("no-throw")
            } catch (e: Throwable) {
                println("copyInto-negative-start")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayCopyContractBoundariesAndOverlap",
            expected:
                """
                [1, 2]
                [1, 2, 3, null, null]
                [1, 2, 3, 30, 40]
                [2, 3]
                [1, 1, 2, 3]
                copyOf-negative
                primitive-copyOf-negative
                copyOfRange-reversed
                copyInto-destination-too-small
                copyInto-negative-start
                """
                + "\n"
        )
    }

    @Test
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

        try assertKotlinOutput(
            source,
            moduleName: "ArraySliceArrayOverloads",
            expected:
                """
                [b, c]
                [d, a]
                [2, 3, 4]
                [30, 10]
                [true, false]
                """
                + "\n"
        )
    }

    @Test
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

        try assertKotlinOutput(
            source,
            moduleName: "SignedArrayViewConversionsFromUnsignedArrays",
            expected:
                """
                [1, 9, 3]
                [10, 20]
                [100, 200]
                [1000, 2000]
                """
                + "\n"
        )
    }

    @Test
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

        try assertKotlinOutput(
            source,
            moduleName: "UnsignedArrayViewConversions",
            expected:
                """
                [1, 9, 3]
                [10, 20]
                [100, 200]
                [1000, 2000]
                """
                + "\n"
        )
    }

    @Test
    func testULongArrayConstructorSemantics() throws {
        let source = """
        fun main() {
            val empty = ULongArray(0)
            println("empty=${empty.size}")

            val zeroInitialized = ULongArray(3)
            println("zero=${zeroInitialized.toList()}")

            try {
                ULongArray(-1)
                println("negative=NO_THROW")
            } catch (e: NegativeArraySizeException) {
                println("negative=NegativeArraySizeException")
            }

            val signed = longArrayOf(1L, -1L, Long.MIN_VALUE)
            val view = signed.asULongArray()
            println("viewBits=${view[0].toLong()},${view[1].toLong()}")
            println("minBitPattern=${view[2].toLong() == Long.MIN_VALUE}")
            signed[1] = 99L
            println("viewAfterWrite=${view[1]}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ULongArrayConstructorSemantics",
            expected:
                """
                empty=0
                zero=[0, 0, 0]
                negative=NegativeArraySizeException
                viewBits=1,-1
                minBitPattern=true
                viewAfterWrite=99
                """
                + "\n"
        )
    }

    @Test
    func testUShortArrayConstructorsPreserveZeroAndSignedStorageSemantics() throws {
        let source = """
        fun main() {
            try {
                UShortArray(-1)
                println("no throw")
            } catch (e: NegativeArraySizeException) {
                println("negative: ${e.message}")
            }

            println(UShortArray(0).size)

            val zeros = UShortArray(3)
            println(zeros[0].toInt())

            val storage = shortArrayOf(1, -1)
            val values = UShortArray(storage)
            val signedView = values.asShortArray()
            println(values.size)
            println(signedView[0])
            println(signedView[1])
            signedView[0] = -2
            println(storage[0])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UShortArrayConstructors",
            expected: "negative: -1\n0\n0\n2\n1\n-1\n-2\n"
        )
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "UnsignedCollectionToPrimitiveArrayConversions", expected: "2\n1\n255\n2\n65535\n2\n4000000000\n2\n4000000000\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "PrimitiveArrayFill", expected: "0\n7\n7\nfalse\ntrue\ntrue\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "PrimitiveArrayCopyOf", expected: "1\n3\n1\n99\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "BoxedIntArrayContentEquals", expected: "true\nfalse\ntrue\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "PrimitiveArrayToListRoundTrip", expected: "3\n10\n30\n2\n200\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "UnsignedPrimitiveArrayAsListView", expected: "3\n200\n900\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "UnsignedPrimitiveArrayToTypedArray", expected: "200\n200\n900\n1000\n1000\n9000\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "UnsignedPrimitiveArrayCopyOfNewSizeAndInit", expected: "2\n1\n4\n10\n20\n700\n700\n10\n1\n10\n100\n9000\n9000\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "UnsignedPrimitiveArrayCopyOfRangeReturnsUnsignedArrays", expected: "0\n0\n2\n200\n200\n900\n2\n2000\n2000\n9000\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ListToIntArrayRoundTrip", expected: "3\n5\n15\n5\n99\n")
    }

    @Test
    func testListToByteArrayRoundTrip() throws {
        let source = """
        fun main() {
            val list = listOf(1.toByte(), (-2).toByte(), 127.toByte())
            val arr = list.toByteArray()
            println(arr.size)
            println(arr[0])
            println(arr[1])
            println(arr[2])

            arr[0] = (-8).toByte()
            println(list[0])
            println(arr[0])
        }
        """
        try assertKotlinOutput(source, moduleName: "ListToByteArrayRoundTrip", expected: "3\n1\n-2\n127\n1\n-8\n")
    }

    @Test
    func testListToLongArrayRoundTrip() throws {
        let source = """
        fun main() {
            val list = listOf(5L, 10L, 15L)
            val arr = list.toLongArray()
            println(arr.size)
            println(arr[0])
            println(arr[2])

            arr[0] = 99L
            println(list[0])
            println(arr[0])
        }
        """
        try assertKotlinOutput(source, moduleName: "ListToLongArrayRoundTrip", expected: "3\n5\n15\n5\n99\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ListToBooleanArrayRoundTrip", expected: "3\nT\nF\nF\nT\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ListToShortArrayRoundTrip", expected: "3\n1\n-2\n32767\n1\n7\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ListToDoubleArrayRoundTrip", expected: "3\n1.5\n-2.25\n0.5\n1.5\n9.25\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ListToFloatArrayRoundTrip", expected: "3\n1.5\n-2.25\n0.5\n1.5\n9.25\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "BoxedIntArrayContentHashCode", expected: "true\nfalse\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ArrayContentDeepToString", expected: "[[1, 2], [x, y], [3, 4]]\n[[...]]\n")
    }

    @Test
    func testArrayContentAndJoinToStringOverloads() throws {
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
            println(boxed.joinToString(","))
            println(intArrayOf(1, -2, 3).joinToString(","))
            println(byteArrayOf(1, (-1).toByte()).joinToString(","))
            println(shortArrayOf(2, (-3).toShort()).joinToString(","))
            println(longArrayOf(1L, 4000000000L).joinToString(","))
            println(floatArrayOf(1.5f, -2.0f).joinToString(","))
            println(doubleArrayOf(2.25, -0.5).joinToString(","))
            println(booleanArrayOf(true, false).joinToString(","))
            println(charArrayOf('a', 'Z').joinToString(","))
            println(ubyteArrayOf(1.toUByte(), 255.toUByte()).joinToString(","))
            println(ushortArrayOf(1.toUShort(), 65535.toUShort()).joinToString(","))
            println(uintArrayOf(1u, 4000000000u).joinToString(","))
            println(ulongArrayOf(1uL, 4000000000uL).joinToString(","))
            println(doubleArrayOf(1.5, 2.5).joinToString())
            println(booleanArrayOf(true, false, true).joinToString(prefix = "[", postfix = "]"))
            println(charArrayOf('a', 'b', 'c').joinToString(""))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ArrayContentAndJoinToStringOverloads",
            expected:
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
                1,two,3
                1,-2,3
                1,-1
                2,-3
                1,4000000000
                1.5,-2.0
                2.25,-0.5
                true,false
                a,Z
                1,255
                1,65535
                1,4000000000
                1,4000000000
                1.5, 2.5
                [true, false, true]
                abc
                """
                + "\n"
        )
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ArrayContentDeepHashCode", expected: "true\nfalse\nfalse\ntrue\nfalse\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "ArrayContentDeepEquals", expected: "true\nfalse\nfalse\ntrue\nfalse\n")
    }

    @Test
    func testSourceBackedArrayContentNullFloatingAndUnsignedEdges() throws {
        let source = """
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            val genericA: Array<Int?> = arrayOf(1, null, 3)
            val genericB: Array<Int?> = arrayOf(1, null, 3)
            val genericC: Array<Int?> = arrayOf(1, 2, 3)
            println(genericA.contentEquals(genericB))
            println(genericA.contentEquals(genericC))
            println(genericA.contentEquals(null))
            val nullableGeneric: Array<Int>? = null
            println(nullableGeneric.contentEquals(null))
            println(genericA.contentHashCode() == genericB.contentHashCode())

            val nested: Array<Any?> = arrayOf(
                arrayOf(arrayOf(1, 2)),
                intArrayOf(3, 4),
                arrayOfNulls<String>(1)
            )
            val nestedSame: Array<Any?> = arrayOf(
                arrayOf(arrayOf(1, 2)),
                intArrayOf(3, 4),
                arrayOfNulls<String>(1)
            )
            println(nested.contentDeepEquals(nestedSame))
            println(nested.contentDeepHashCode() == nestedSame.contentDeepHashCode())
            println(nested.contentDeepToString())

            val self: Array<Any?> = arrayOfNulls(1)
            self[0] = self
            println(self.contentDeepEquals(self))
            println(self.contentDeepToString())

            val floats = floatArrayOf(Float.NaN, -0.0f)
            val sameFloats = floatArrayOf(Float.NaN, -0.0f)
            val differentZero = floatArrayOf(Float.NaN, 0.0f)
            println(floats.contentEquals(sameFloats))
            println(floats.contentEquals(differentZero))
            println(floats.contentHashCode() == sameFloats.contentHashCode())
            println(floats.contentToString())

            val unsigned = uintArrayOf(1u, 4_000_000_000u)
            val sameUnsigned = uintArrayOf(1u, 4_000_000_000u)
            println(unsigned.contentEquals(sameUnsigned))
            println(unsigned.contentHashCode() == sameUnsigned.contentHashCode())
            println(unsigned.contentToString())
            println(unsigned.contentEquals(null))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SourceBackedArrayContentNullFloatingUnsignedEdges",
            expected:
                """
                true
                false
                false
                true
                true
                true
                true
                [[[1, 2]], [3, 4], [null]]
                true
                [[...]]
                true
                false
                true
                [NaN, -0.0]
                true
                true
                [1, 4000000000]
                false
                """
                + "\n"
        )
    }

    // KSP-481 follow-up: `for (i in 0 until n)` used to leave `i` typed as Any
    // (see testCodegenForLoopUntilRangeExplicitIntType), which made ByteArray's
    // indexed `get(index: Int)` unresolvable and surfaced as a TYPE-0001 error
    // pointing at both operands of `a[i] != b[i]`. Locks in that indexing +
    // comparison combination now that the loop variable is correctly typed Int.
    @Test
    func testByteArrayElementNotEqualsInsideUntilRangeLoop() throws {
        let source = """
        fun main() {
            val a = byteArrayOf(1, 2, 3, 4)
            val b = byteArrayOf(1, 2, 3, 4)
            var match = true
            for (i in 0 until a.size) {
                if (a[i] != b[i]) {
                    match = false
                }
            }
            println(match)

            val c = byteArrayOf(1, 2, 3, 5)
            var match2 = true
            for (i in 0 until a.size) {
                if (a[i] != c[i]) {
                    match2 = false
                }
            }
            println(match2)
        }
        """
        try assertKotlinOutput(source, moduleName: "ByteArrayElementNotEqualsInsideUntilRangeLoop", expected: "true\nfalse\n")
    }
}
#endif
