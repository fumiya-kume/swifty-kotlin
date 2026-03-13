fun main() {
    println(sequenceOf(3, 1, 2).sorted().toList())
    println(sequenceOf("cc", "a", "bbb").sortedBy { it.length }.toList())
    println(sequenceOf(3, 1, 2).sortedDescending().toList())
}
