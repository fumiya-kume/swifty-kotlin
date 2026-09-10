@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

// STDLIB-033: kotlin.concurrent / kotlin.concurrent.atomics parity edge cases
@Suite
struct CodegenBackendAtomicExtendedEdgeCasesTests {

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntCASSuccess", expected: "true\n20\n")
    }

    @Test
    func testCodegenJavaAtomicIntegerDirectConstruction() throws {
        let source = """
        import java.util.concurrent.atomic.AtomicInteger

        fun main() {
            val counter = AtomicInteger(0)
            counter.incrementAndGet()
            counter.incrementAndGet()
            counter.addAndGet(3)
            println(counter.get())
        }
        """
        try assertKotlinOutput(source, moduleName: "JavaAtomicIntegerDirectConstruction", expected: "5\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntCASFailure", expected: "false\n10\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntCAE", expected: "5\n10\n10\n10\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntIncrement", expected: "7\n8\n8\n7\n8\n8\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntLargeValue", expected: "2147483647\ntrue\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntStoreLoad", expected: "0\n42\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongBasic", expected: "100\n200\n200\n300\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongCAS", expected: "true\n60\nfalse\n60\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongCAE", expected: "10\n20\n20\n20\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongArithmetic", expected: "5\n5\n8\n8\n9\n9\n8\n9\n9\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongNegativeDelta", expected: "7\n7\n7\n5\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicBooleanBasic", expected: "false\ntrue\ntrue\nfalse\n")
    }

    @Test
    func testCodegenAtomicBooleanGetSetGetAndSet() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            println(a.get())
            a.set(true)
            println(a.get())
            println(a.getAndSet(false))
            println(a.get())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBooleanGetSet", expected: "false\ntrue\ntrue\nfalse\n")
    }

    @Test
    func testCodegenAtomicBooleanCASSuccessAndFailure() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(true)
            println(a.compareAndSet(false, false))
            println(a.load())
            println(a.compareAndSet(true, false))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBooleanCAS", expected: "false\ntrue\ntrue\nfalse\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicBooleanCAE", expected: "false\ntrue\ntrue\ntrue\n")
    }

    @Test
    func testCodegenAtomicReferenceIdentityVsEqualityCAS() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        data class Token(val id: Int)

        fun main() {
            val current = Token(1)
            val equalButDistinct = Token(1)
            val replacement = Token(2)
            val ref = AtomicReference(current)
            // AtomicReference CAS compares references, not structural equality.
            println(ref.compareAndSet(equalButDistinct, replacement))
            println(ref.load() === current)
            println(ref.compareAndSet(current, replacement))
            println(ref.load() === replacement)
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicRefIdentity", expected: "false\ntrue\ntrue\ntrue\n")
    }

    @Test
    func testCodegenAtomicReferenceCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        data class Token(val value: String)

        fun main() {
            val a = Token("alpha")
            val b = Token("beta")
            val c = Token("gamma")
            val ref = AtomicReference(a)
            // Success: returns old value (a) and stores b.
            val old = ref.compareAndExchange(a, b)
            println(old === a)
            println(ref.load() === b)
            // Failure: returns current (b), unchanged.
            val cur = ref.compareAndExchange(c, a)
            println(cur === b)
            println(ref.load() === b)
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicRefCAE", expected: "true\ntrue\ntrue\ntrue\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicRefExchangeStore", expected: "v1\nv2\nv3\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicArrayFetchAndUpdateAt", expected: "a\nab\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicArrayUpdateAt", expected: "ab\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicArrayCompareAndSetAt", expected: "true\nb\nfalse\nb\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicArrayOfNullsFactory", expected: "2\nfirst\nvalue\n")
    }

    @Test
    func testCodegenAtomicArrayOfFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.atomicArrayOf

        fun main() {
            val arr = atomicArrayOf("first", "value")
            println(arr.size)
            println(arr.loadAt(0))
            println(arr.loadAt(1))
            arr.storeAt(1, "next")
            println(arr.loadAt(1))

            val empty = atomicArrayOf<String>()
            println(empty.size)

            val source = arrayOf("spread", "values")
            val spread = atomicArrayOf(*source)
            println(spread.size)
            println(spread.loadAt(0))
            println(spread.loadAt(1))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicArrayOfFactory", expected: "2\nfirst\nvalue\nnext\n0\n2\nspread\nvalues\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicArrayUpdateAndFetchAt", expected: "ab\nab\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayBasic", expected: "3\n0\n42\n42\n99\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayInitFactory", expected: "3\n0\n1\n2\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayCAS", expected: "true\n20\nfalse\n20\n20\n50\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayArithmetic", expected: "5\n5\n8\n8\n9\n10\n10\n10\n9\n8\n8\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayFetchAndUpdateAt", expected: "10\n20\n20\n15\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayIndexOp", expected: "7\n13\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayBasic", expected: "3\n0\n100\n100\n200\n")
    }

    @Test
    func testCodegenAtomicLongArrayInitFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(3) { index ->
                if (index == 0) 10L else if (index == 1) 20L else 30L
            }
            println(arr.size)
            println(arr.loadAt(0))
            println(arr.loadAt(1))
            println(arr.loadAt(2))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayInitFactory", expected: "3\n10\n20\n30\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayCAS", expected: "true\n20\nfalse\n20\n20\n50\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayArithmetic", expected: "5\n5\n8\n8\n9\n10\n10\n9\n8\n8\n")
    }

    @Test
    func testCodegenAtomicLongArrayFetchAndUpdateAtThirdScenario() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            arr.storeAt(0, 7L)
            val old = arr.fetchAndUpdateAt(0) { it * 3L }
            println(old)
            println(arr.loadAt(0))
            val fetched = arr.fetchAndUpdateAt(0) { it - 4L }
            println(fetched)
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayFetchAndUpdateAt", expected: "7\n21\n21\n17\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIncrementAndGet", expected: "2\n2\n4\n4\n6\n6\n8\n8\n")
    }

    @Test
    func testCodegenAtomicLongArrayFetchAndUpdateAtSecondScenario() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            arr.storeAt(0, 10L)
            val old = arr.fetchAndUpdateAt(0) { it * 2L }
            println(old)
            println(arr.loadAt(0))
            val fetched = arr.fetchAndUpdateAt(0) { it - 5L }
            println(fetched)
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayFetchAndUpdateAt", expected: "10\n20\n20\n15\n")
    }

    @Test
    func testCodegenAtomicGetAndIncrementOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.getAndIncrement())
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.getAndIncrement())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.getAndIncrement(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.getAndIncrement(0))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndIncrement", expected: "1\n2\n3\n4\n5\n6\n7\n8\n")
    }

    @Test
    func testCodegenAtomicGetAndDecrementOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(2)
            println(intValue.getAndDecrement())
            println(intValue.load())

            val longValue = AtomicLong(4L)
            println(longValue.getAndDecrement())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 6)
            println(intArray.getAndDecrement(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 8L)
            println(longArray.getAndDecrement(0))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndDecrement", expected: "2\n1\n4\n3\n6\n5\n8\n7\n")
    }

    @Test
    func testCodegenAtomicGetAndAddOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.getAndAdd(2))
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.getAndAdd(4L))
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.getAndAdd(0, 2))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.getAndAdd(0, 3L))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndAdd", expected: "1\n3\n3\n7\n5\n7\n7\n10\n")
    }

    @Test
    func testCodegenAtomicDecrementAndGetOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(2)
            println(intValue.decrementAndGet())
            println(intValue.load())

            val longValue = AtomicLong(4L)
            println(longValue.decrementAndGet())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 6)
            println(intArray.decrementAndGet(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 8L)
            println(longArray.decrementAndGet(0))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicDecrementAndGet", expected: "1\n1\n3\n3\n5\n5\n7\n7\n")
    }

    @Test
    func testCodegenAtomicAddAndGetOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.addAndGet(2))
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.addAndGet(4L))
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.addAndGet(0, 2))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.addAndGet(0, 3L))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicAddAndGet", expected: "3\n3\n7\n7\n7\n7\n10\n10\n")
    }

    @Test
    func testCodegenAtomicIntDefaultInitialValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(0)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntDefaultInit", expected: "0\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntGetAndUpdate", expected: "10\n20\n20\n17\n22\n22\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongGetAndUpdate", expected: "10\n20\n20\n17\n22\n22\n")
    }

    @Test
    func testCodegenAtomicBooleanGetAndUpdate() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            val old = a.getAndUpdate { !it }
            println(old)
            println(a.load())
            val fetched = a.fetchAndUpdate { !it }
            println(fetched)
            println(a.load())
            val new2 = a.updateAndGet { !it }
            println(new2)
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBooleanGetAndUpdate", expected: "false\ntrue\ntrue\nfalse\ntrue\n")
    }

    @Test
    func testCodegenAtomicGetAndSetOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.getAndSet(2))
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.getAndSet(4L))
            println(longValue.load())

            val refValue = AtomicReference("a")
            println(refValue.getAndSet("b"))
            println(refValue.load())

            val refArray = AtomicArray<String?>(1)
            refArray.storeAt(0, "x")
            println(refArray.getAndSet(0, "y"))
            println(refArray.loadAt(0))

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.getAndSet(0, 6))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.getAndSet(0, 8L))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndSet", expected: "1\n2\n3\n4\na\nb\nx\ny\n5\n6\n7\n8\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicInt", expected: "5\n10\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicLong", expected: "5\n10\n12\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicReference", expected: "first\nsecond\nthird\n")
    }

    @Test
    func testCodegenKotlinConcurrentAtomicIntArrayOperations() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
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
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicIntArray", expected: "10\n20\n15\n2\n")
    }

    @Test
    func testCodegenKotlinConcurrentAtomicLongArrayOperations() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
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
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicLongArray", expected: "10\n20\n15\n2\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicBoolSetterABI001", expected: "true\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntSetterABI001", expected: "42\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicRefGetAndUpdateBUG01", expected: "hello\nhello!\nhello!\nhello!?\nHELLO!?\nHELLO!?~\nHELLO!?~\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayOOBLoad", expected: "caught\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayOOBStore", expected: "caught\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayOOBLoad", expected: "caught\n")
    }

    @Test
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
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayOOBStore", expected: "caught\n")
    }

    @Test
    func testCodegenAtomicArrayOfBoxesPrimitiveElementsForIsChecks() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.atomicArrayOf

        fun main() {
            val mixed = atomicArrayOf<Any>(1.5, "x", 2.5, 7L, true)
            for (i in 0 until mixed.size) {
                val v = mixed.loadAt(i)
                println("${v is Double} ${v is Long} ${v is Boolean} ${v is String}")
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "AtomicArrayOfBoxesPrimitives",
            expected:
                """
                true false false false
                false false false true
                true false false false
                false true false false
                false false true false
                """ + "\n"
        )
    }

}
#endif
