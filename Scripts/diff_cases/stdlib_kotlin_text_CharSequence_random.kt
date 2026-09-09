import kotlin.random.Random

private fun isExpected(value: Char): Boolean = value == 'a' || value == 'b' || value == 'c'

fun main() {
    val value: CharSequence = "abc"

    println(isExpected(value.random()))
    println(isExpected("abc".random()))
    println(isExpected(value.random(Random(7))))
    println(isExpected("abc".random(Random(7))))
    println(value.randomOrNull() != null)
    println("abc".randomOrNull(Random(7)) != null)
    println("".randomOrNull() == null)

    try {
        "".random(Random(1))
        println(false)
    } catch (_: NoSuchElementException) {
        println(true)
    }
}
