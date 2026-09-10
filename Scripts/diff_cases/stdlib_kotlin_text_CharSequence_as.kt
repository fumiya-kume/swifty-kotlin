// KSP-1365: CharSequence asIterable/asSequence preserve Char values, remain
// repeatable, and observe mutations made after the lazy views are created.
fun main() {
    val text: CharSequence = "ab"
    val iterable: Iterable<Char> = text.asIterable()
    val sequence: Sequence<Char> = text.asSequence()
    println(iterable.toList())
    println(iterable.toList())
    println(sequence.toList())
    println(sequence.toList())

    val empty: CharSequence = ""
    println(empty.asIterable() is List<*>)
    println(empty.asIterable().toList())
    println(empty.asSequence().toList())

    val builder = StringBuilder("x")
    val builderIterable: Iterable<Char> = builder.asIterable()
    val builderSequence: Sequence<Char> = builder.asSequence()
    builder.append("y")
    println(builderIterable.toList())
    println(builderSequence.toList())
}
