// RF-FIXTURE-022: String substring extraction overloads.
package golden.sema

fun useSubstring1(): String = "hello".substring(1)

fun useSubstring2(): String = "hello".substring(1, 3)

fun useSubstringBefore(): String = "hello.world.kt".substringBefore(".")

fun useSubstringAfter(): String = "hello.world.kt".substringAfter(".")

fun useSubstringBeforeLast(): String = "hello.world.kt".substringBeforeLast(".")

fun useSubstringAfterLast(): String = "hello.world.kt".substringAfterLast(".")
