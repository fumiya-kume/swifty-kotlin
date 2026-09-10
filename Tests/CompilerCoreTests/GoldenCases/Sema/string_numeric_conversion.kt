// RF-FIXTURE-022: String numeric conversions — strict and OrNull (nullable)
// variants. The valid/invalid split is runtime behavior; only one input per
// signature is kept here.
package golden.sema

fun useToInt(): Int = "42".toInt()

fun useToDouble(): Double = "3.14".toDouble()

fun useToIntOrNull(): Int? = "123".toIntOrNull()

fun useToDoubleOrNull(): Double? = " 3.14 ".toDoubleOrNull()
