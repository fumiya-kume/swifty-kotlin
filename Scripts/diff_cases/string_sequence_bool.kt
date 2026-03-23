fun main() {
    println("hello".asSequence().toList())
    println("a".singleOrNull())
    println("ab".singleOrNull())
    println("".singleOrNull())
    println("true".toBooleanStrict())
    println("false".toBooleanStrict())
    try { "yes".toBooleanStrict() } catch (e: IllegalArgumentException) { println("caught: ${e.message}") }
}
