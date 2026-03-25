fun main() {
    println(sequenceOf(3, 1, 2).sorted().toList())
    println(sequenceOf("cc", "a", "bbb").sortedBy { it.length }.toList())
    println(sequenceOf(1, 2, 3).sortedBy {
        when (it) {
            1 -> "banana"
            2 -> "apple"
            else -> "carrot"
        }
    }.toList())
    println(sequenceOf(3, 1, 2).sortedDescending().toList())
}
