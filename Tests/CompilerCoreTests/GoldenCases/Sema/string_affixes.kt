// RF-FIXTURE-022: String prefix / suffix / containment checks and removal.
package golden.sema

fun useStartsWith(): Boolean = "Kotlin".startsWith("Ko")

fun useEndsWith(): Boolean = "Kotlin".endsWith("lin")

fun useContains(): Boolean = "Kotlin".contains("otl")

fun useRemovePrefix(): String = "hello".removePrefix("he")

fun useRemoveSuffix(): String = "hello".removeSuffix("lo")

fun useRemoveSurrounding1(): String = "[hello]".removeSurrounding("[", "]")

fun useRemoveSurrounding2(): String = "**foo**".removeSurrounding("*")
