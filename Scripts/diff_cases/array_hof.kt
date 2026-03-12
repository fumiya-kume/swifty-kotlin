fun main() {
    val arr = arrayOf(1, 2, 3)
    println(arr.map { it * 2 })
    println(arr.filter { it > 1 })
    arr.forEach { print(it) }
    println()
}
