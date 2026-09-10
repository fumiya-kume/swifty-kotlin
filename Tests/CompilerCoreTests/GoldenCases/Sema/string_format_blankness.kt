// RF-FIXTURE-022: String.format and blankness / first-element checks.
package golden.sema

fun useFormat(): String = "%s:%d".format("age", 7)

fun useIsEmpty(): Boolean = "".isEmpty()

fun useIsNotEmpty(): Boolean = "x".isNotEmpty()

fun useIsBlank(): Boolean = "  ".isBlank()

fun useIsNotBlank(): Boolean = "x".isNotBlank()

fun useFirst(): Char = "hello".first()

fun useFirstOrNull(): Char? = "".firstOrNull()
