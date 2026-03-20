fun main() {
    // lineSequence returns Sequence<String>, lines returns List<String>
    // Both split on \n, \r, \r\n
    val text = "a\nb\nc"
    println(text.lineSequence().toList())
    println(text.lines())

    println("hello".lineSequence().toList())
    println("hello".lines())

    println("".lineSequence().toList())
    println("".lines())

    println("a\n\nb".lineSequence().toList())
    println("a\n\nb".lines())
}
