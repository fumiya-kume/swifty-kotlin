// RF-FIXTURE-022: String replace / split overloads.
package golden.sema

fun useReplace(): String = "abc".replace("a", "z")

fun useReplaceFirst(): String = "abcabc".replaceFirst("abc", "X")

fun useReplaceFirstIgnoreCase(): String = "abcABC".replaceFirst("abc", "X", ignoreCase = true)

fun useReplaceRange(): String = "hello".replaceRange(0..2, "HE")

fun useSplit(): List<String> = "1,2,3".split(",")
