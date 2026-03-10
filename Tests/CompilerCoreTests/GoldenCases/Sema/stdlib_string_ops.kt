package golden.sema

fun useTrim(): String = "  hi  ".trim()

fun useSplit(): List<String> = "1,2,3".split(",")

fun useReplace(): String = "abc".replace("a", "z")

fun useStartsWith(): Boolean = "Kotlin".startsWith("Ko")

fun useEndsWith(): Boolean = "Kotlin".endsWith("lin")

fun useContains(): Boolean = "Kotlin".contains("otl")

fun useToInt(): Int = "42".toInt()

fun useToDouble(): Double = "3.14".toDouble()

fun useFormat(): String = "%s:%d".format("age", 7)

fun useSubstring1(): String = "hello".substring(1)

fun useSubstring2(): String = "hello".substring(1, 3)

fun useLowercase(): String = "Hello".lowercase()

fun useUppercase(): String = "Hello".uppercase()

fun useToIntOrNullValid(): Int? = "123".toIntOrNull()

fun useToIntOrNullInvalid(): Int? = "abc".toIntOrNull()

fun useToDoubleOrNullValid(): Double? = " 3.14 ".toDoubleOrNull()

fun useToDoubleOrNullInvalid(): Double? = "abc".toDoubleOrNull()
