fun main() {
    println(sequenceOf(1, 2, 3).joinToString(", "))
    println(sequenceOf("a", "b", "c").joinToString("-"))
    println(listOf<String>().asSequence().joinToString(prefix = "<", postfix = ">"))
    println(sequenceOf(1, 2, 3).joinToString(separator = ":", prefix = "[", postfix = "]"))
}
