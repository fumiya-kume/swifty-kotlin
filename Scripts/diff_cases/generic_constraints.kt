fun <T> maxItem(a: T, b: T): T where T : Comparable<T> = if (a > b) a else b
fun <T : Comparable<T>> clamp(value: T, min: T, max: T): T = when {
    value < min -> min
    value > max -> max
    else -> value
}
fun main() {
    println(maxItem(3, 7))
    println(maxItem("apple", "banana"))
    println(clamp(5, 1, 10))
    println(clamp(15, 1, 10))
    println(clamp(-5, 1, 10))
}
