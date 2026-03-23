// SKIP-DIFF  -- requires callable val (invoke operator on lambda variables)
fun main() {
    // Nested lambda captures
    val x = 10
    val outer = { y: Int ->
        val inner = { z: Int -> x + y + z }
        inner(1)
    }
    println(outer(20))

    // Lambda returning lambda
    val adder = { a: Int -> { b: Int -> a + b } }
    val add5 = adder(5)
    println(add5(3))
    println(add5(10))

    // Triple nesting
    val a = 1
    val f = {
        val b = 2
        val g = {
            val c = 3
            a + b + c
        }
        g()
    }
    println(f())
}
