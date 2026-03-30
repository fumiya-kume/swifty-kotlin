// Test STDLIB-GEN-055: Complete type constraint support

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

fun main() {
    // Single upper bound constraint with Int
    println(clamp(5, 1, 10))
    println(clamp(15, 1, 10))
    println(clamp(-5, 1, 10))

    // Single upper bound constraint with String
    println(clamp("b", "a", "c"))

    // Where clause with Int and String
    println(maxItem(3, 7))
    println(maxItem("apple", "banana"))

    // Multiple constraints via where clause
    println(processItem(42))
    println(processItem("hello"))

    // Generic class with Int
    val intBox = BoundedBox(5)
    println(intBox.isLessThan(10))
    println(intBox.isGreaterThan(3))
    println(intBox.describe())

    // Generic class with String
    val strBox = BoundedBox("hello")
    println(strBox.isLessThan("world"))
    println(strBox.describe())
}
