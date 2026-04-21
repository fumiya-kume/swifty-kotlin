// STDLIB-SEQ-002: generateSequence with null termination and infinite source + take
fun main() {
    // Null termination: sequence ends when nextFunction returns null
    val s1 = generateSequence(1) { if (it < 5) it + 1 else null }.toList()
    println(s1)

    // Infinite source with take
    val s2 = generateSequence(1) { it + 1 }.take(5).toList()
    println(s2)

    // Null termination: seed-function variant
    val s3 = generateSequence({ 10 }) { if (it > 1) it / 2 else null }.toList()
    println(s3)

    // Unseeded variant with explicitly typed lambda
    val fn: () -> Int? = { 42 }
    val s4 = generateSequence(fn).take(3).toList()
    println(s4)
}
