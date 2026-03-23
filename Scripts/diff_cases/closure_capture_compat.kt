// SKIP-DIFF  -- several cases require callable val / Ref boxing (not yet implemented)
// CLSR-001: Comprehensive closure capture Kotlin compatibility test
fun main() {
    // === 1. Immutable (val) capture ===
    val x = 10
    val nums = listOf(1, 2, 3)
    println(nums.map { it + x })  // [11, 12, 13]

    // === 2. Multiple val captures ===
    val base = 100
    val scale = 2
    println(listOf(1, 2, 3).map { it * scale + base })  // [102, 104, 106]

    // === 3. Mutable capture (var) — requires Ref boxing ===
    // In Kotlin, var captured by lambda must be boxed in IntRef/ObjectRef
    // so mutations are visible to the outer scope.
    var counter = 0
    val inc = { counter++ }
    inc()
    inc()
    println(counter) // should be 2

    // === 4. Nested lambda captures ===
    val outer = 10
    val f = {
        val inner = 20
        val g = { outer + inner }
        g()
    }
    println(f()) // should be 30

    // === 5. Lambda returning lambda ===
    fun adder(n: Int): (Int) -> Int = { it + n }
    val add5 = adder(5)
    println(add5(10)) // should be 15

    // === 6. Captured in loop ===
    val fns = mutableListOf<() -> Int>()
    for (i in 0..2) {
        fns.add { i }
    }
    println(fns.map { it() }) // should be [0, 1, 2]

    // === 7. Val capture in filter ===
    val threshold = 3
    println(listOf(1, 2, 3, 4, 5).filter { it > threshold })  // [4, 5]

    // === 8. Val capture in forEach ===
    val prefix = "item="
    listOf(1, 2, 3).forEach { println(prefix + it.toString()) }
    // item=1
    // item=2
    // item=3

    // === 9. Three captures in map ===
    val a = 1
    val b = 10
    val c = 100
    println(listOf(1, 2, 3).map { it + a + b + c })  // [112, 113, 114]
}
