fun isPositive(n: Int): Boolean = n > 0
fun negate(x: Int): Int = -x
fun square(x: Int): Int = x * x

class Counter(var count: Int) {
    fun addTo(n: Int): Int = count + n
}

fun main() {
    // 1. ::functionName as function reference (usable as lambda arg)
    val ref = ::negate
    println(ref(5))

    // 2. Callable ref with map HOF
    val nums = listOf(1, 2, 3)
    val negated = nums.map(::negate)
    println(negated)

    // 3. Callable ref with filter HOF: list.filter(::isPositive)
    val mixed = listOf(-2, -1, 0, 1, 2, 3)
    val positives = mixed.filter(::isPositive)
    println(positives)

    // 4. obj::memberFunction as bound member reference
    val counter = Counter(10)
    val boundAdd = counter::addTo
    println(boundAdd(5))

    // 5. Bound member ref invoked inline (must parenthesize per Kotlin spec)
    println((Counter(100)::addTo)(42))

    // 6. Chained callable refs: filter then map
    val data = listOf(-3, -1, 0, 2, 4)
    val result = data.filter(::isPositive).map(::square)
    println(result)

    // 7. Callable ref invoked directly
    println((::square)(6))
}
