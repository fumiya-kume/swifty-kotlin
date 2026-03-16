fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.binarySearch(3))
    println(list.binarySearch(1))
    println(list.binarySearch(5))
    println(list.binarySearch(0))
}
