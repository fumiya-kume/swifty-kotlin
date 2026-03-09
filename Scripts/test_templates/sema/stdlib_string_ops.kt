package golden.sema

fun useTrim(): String = "  hi  ".trim()

fun useSplit(): List<String> = "1,2,3".split(",")

fun useReplace(): String = "abc".replace("a", "z")

fun useStartsWith(): Boolean = "Kotlin".startsWith("Ko")

fun useEndsWith(): Boolean = "Kotlin".endsWith("lin", true)

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

fun useIndexOf(): Int = "abcabc".indexOf("bc")

fun useLastIndexOf(): Int = "abcabc".lastIndexOf("bc")

fun useReversed(): String = "abc".reversed()

fun useToList(): List<Char> = "abc".toList()

fun useToCharArray(): List<Char> = "abc".toCharArray()

fun useTake(): String = "abcde".take(3)

fun useDrop(): String = "abcde".drop(2)

fun useTakeLast(): String = "abcde".takeLast(2)

fun useDropLast(): String = "abcde".dropLast(2)

fun usePadStart(): String = "42".padStart(5, '0')

fun usePadEnd(): String = "42".padEnd(5, '0')

fun useRepeat(): String = "ab".repeat(3)
