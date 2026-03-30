package golden.sema

// Single upper bound constraint: <T : Comparable<T>>
fun <T : Comparable<T>> clamp(value: T, min: T, max: T): T = when {
    value < min -> min
    value > max -> max
    else -> value
}

// Where clause single constraint: fun <T> f(...) where T : Comparable<T>
fun <T> maxItem(a: T, b: T): T where T : Comparable<T> = if (a > b) a else b

// Multiple constraints via where clause: where T : Comparable<T>, T : Any
fun <T> processItem(v: T): String where T : Comparable<T>, T : Any = v.toString()

// Generic class with upper bound constraint: class Foo<T : Comparable<T>>
class BoundedBox<T : Comparable<T>>(val value: T) {
    fun isLessThan(other: T): Boolean = value < other
    fun isGreaterThan(other: T): Boolean = value > other
    fun describe(): String = value.toString()
}

fun useConstraints() {
    val c1 = clamp(5, 1, 10)
    val c2 = clamp("b", "a", "c")
    val m1 = maxItem(3, 7)
    val m2 = maxItem("apple", "banana")
    val p1 = processItem(42)
    val p2 = processItem("hello")
    val box = BoundedBox(5)
    val lt = box.isLessThan(10)
    val gt = box.isGreaterThan(3)
    val desc = box.describe()
}
