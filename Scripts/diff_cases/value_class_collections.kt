// SKIP-DIFF
@JvmInline
value class Score(val value: Int)

@JvmInline
value class Name(val value: String)

fun main() {
    val scores = listOf(Score(80), Score(95), Score(70), Score(88))
    println(scores.size)

    val maxScore = scores.maxByOrNull { it.value }
    println(maxScore?.value)

    val filtered = scores.filter { it.value >= 85 }
    for (s in filtered) {
        println(s.value)
    }

    val mapped = scores.map { Score(it.value + 5) }
    for (s in mapped) {
        println(s.value)
    }

    val nameMap = mapOf(
        Name("Alice") to Score(90),
        Name("Bob") to Score(75)
    )
    println(nameMap[Name("Alice")]?.value)
    println(nameMap[Name("Bob")]?.value)

    val arr = arrayOf(Score(1), Score(2), Score(3))
    println(arr.size)
    for (s in arr) {
        println(s.value)
    }
}
