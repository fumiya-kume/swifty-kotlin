fun main() {
    val left = listOf(1, 2, 3)
    val right = listOf("a", "b")
    val zipped = left.zip(right)
    println(zipped)
    println(zipped.unzip())
}
