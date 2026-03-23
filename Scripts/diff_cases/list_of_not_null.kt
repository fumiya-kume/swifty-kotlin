fun main() {
    println(listOfNotNull(1, null, 2, null, 3))
    println(listOfNotNull<Int>(null, null))
    println(listOfNotNull("a", null, "b"))
    println(listOfNotNull<String>())
}
