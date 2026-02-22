class Counter(start: Int) {
    constructor() : this(0)
}

fun add(a: Int, b: Int): Int = a + b

fun main() {
    val c = Counter(1)
    val d = Counter()
    println(add(20, 22))
}
