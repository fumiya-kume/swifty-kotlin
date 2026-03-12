package golden.sema

fun catchIllegalArgument(): String =
    try { throw IllegalArgumentException("bad") }
    catch (e: IllegalArgumentException) { "caught" }

fun catchIllegalState(): String =
    try { throw IllegalStateException("bad state") }
    catch (e: IllegalStateException) { "caught" }

fun catchIndexOutOfBounds(): String =
    try { throw IndexOutOfBoundsException("index 5") }
    catch (e: IndexOutOfBoundsException) { "caught" }

fun catchUnsupportedOperation(): String =
    try { throw UnsupportedOperationException("not supported") }
    catch (e: UnsupportedOperationException) { "caught" }

fun catchNoSuchElement(): String =
    try { throw NoSuchElementException("empty") }
    catch (e: NoSuchElementException) { "caught" }

fun catchArithmetic(): String =
    try { throw ArithmeticException("div by zero") }
    catch (e: ArithmeticException) { "caught" }

fun catchClassCast(): String =
    try { throw ClassCastException("bad cast") }
    catch (e: ClassCastException) { "caught" }

fun throwableProperties(): String {
    return try { throw RuntimeException("test") }
    catch (e: Throwable) {
        val msg: String? = e.message
        val cause: Throwable? = e.cause
        val trace: String = e.stackTraceToString()
        msg ?: "null"
    }
}
