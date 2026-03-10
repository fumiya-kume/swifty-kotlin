fun main() {
    val values = listOf(1, 2, 3)
    println(values.associateBy { it % 2 })
    println(values.associateWith { it * 10 })
    println(values.associate { (it % 2) to (it * 10) })
}
