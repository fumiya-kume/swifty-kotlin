// CLASS-007: constructor init block and primary constructor property init order
// Verifies basic constructor delegation with primary and secondary constructors.

class Counter(start: Int) {
    constructor() : this(0)
}

fun add(a: Int, b: Int): Int = a + b

fun main() {
    val c = Counter(10)
    val d = Counter()
    println(add(3, 4))
}
