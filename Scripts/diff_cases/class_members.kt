class Counter(val initial: Int) {
    var count: Int = initial

    fun increment() {
        count = count + 1
    }

    fun get(): Int = count
}

fun main() {
    val c = Counter(0)
    c.increment()
    println(c.get())
}
