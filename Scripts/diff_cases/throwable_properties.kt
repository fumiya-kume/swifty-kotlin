fun main() {
    val cause = RuntimeException("root cause")
    val ex = IllegalStateException("wrapper", cause)
    println(ex.message)
    println(ex.cause?.message)

    try { throw NumberFormatException("bad number") } catch (e: NumberFormatException) { println(e.message) }
    try { throw ArithmeticException("div by zero") } catch (e: ArithmeticException) { println(e.message) }
    try { throw IndexOutOfBoundsException("index 5") } catch (e: IndexOutOfBoundsException) { println(e.message) }
    try { throw NoSuchElementException("empty") } catch (e: NoSuchElementException) { println(e.message) }
    try { throw UnsupportedOperationException("nope") } catch (e: UnsupportedOperationException) { println(e.message) }
    try { throw ClassCastException("cast fail") } catch (e: ClassCastException) { println(e.message) }

    val primary = RuntimeException("primary")
    primary.addSuppressed(IllegalArgumentException("suppressed"))
    val suppressed = primary.suppressedExceptions
    println(suppressed.size)
    println(suppressed[0].message)
}
