// RF-FIXTURE-022: String trim / indent APIs.
package golden.sema

fun useTrim(): String = "  hi  ".trim()

fun usePrependIndent(): String = "abc\ndef".prependIndent("  ")

fun useReplaceIndent(): String = "  abc\n  def".replaceIndent("")
