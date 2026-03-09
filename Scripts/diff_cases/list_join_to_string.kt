fun main() {
    val list = listOf(1, 2, 3)
    println(list.joinToString())
    println(list.joinToString(" | "))
    println(list.joinToString(prefix = "<", postfix = ">"))
    println(list.joinToString(separator = ":", prefix = "[", postfix = "]"))
}
