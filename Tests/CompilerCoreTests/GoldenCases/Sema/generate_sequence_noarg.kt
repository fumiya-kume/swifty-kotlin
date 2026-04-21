fun main() {
    // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
    var count = 0
    val gen = generateSequence {
        count++
        if (count <= 5) count else null
    }
    val result = gen.take(3).toList()
    println(result)

    // 1-arg form with take (infinite source)
    var n = 0
    val naturals = generateSequence { ++n }
    val first5 = naturals.take(5).toList()
    println(first5)
}
