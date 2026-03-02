class Counter {
    var count: Int = 0
        get() = field
        set(value) { field = value }

    val label: String get() = "Count"

    fun increment() {
        count = count + 1
    }
}

fun main() {
    val c = Counter()
    println(c.label)
    c.increment()
    println(c.count)
}
