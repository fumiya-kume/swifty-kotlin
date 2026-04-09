fun main() {
    val generated = generateSequence(1) { current -> if (current >= 3) null else current + 1 }
    println(generated.take(2).toList())

    val filtered = sequenceOf(1, 2, 3, 4)
        .map { it * 2 }
        .filter { it % 4 == 0 }

    println(filtered.take(1).toList())
    println(filtered.toList())
}
