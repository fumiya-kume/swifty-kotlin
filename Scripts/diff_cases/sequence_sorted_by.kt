fun main() {
    println(sequenceOf("cc", "a", "bbb").sortedBy { it.length }.toList())
    println(sequenceOf(1, 2, 3).sortedBy {
        when (it) {
            1 -> "banana"
            2 -> "apple"
            else -> "carrot"
        }
    }.toList())
}
