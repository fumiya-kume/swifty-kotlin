fun main() {
    println(sequenceOf("cc", "a", "bbb").sortedByDescending { it.length }.toList())
    println(sequenceOf(1, 2, 3).sortedByDescending {
        when (it) {
            1 -> "banana"
            2 -> "apple"
            else -> "carrot"
        }
    }.toList())
}
