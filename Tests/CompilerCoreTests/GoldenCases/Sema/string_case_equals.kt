// RF-FIXTURE-022: String case conversion and equality overloads.
package golden.sema

fun useLowercase(): String = "Hello".lowercase()

fun useUppercase(): String = "Hello".uppercase()

fun useEquals(): Boolean = "abc".equals("abc")

fun useEqualsIgnoreCase(): Boolean = "abc".equals("ABC", ignoreCase = true)
