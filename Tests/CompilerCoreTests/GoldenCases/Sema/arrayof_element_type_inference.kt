// RF-FIXTURE-002: arrayOf infers its element type from the argument types.

fun arrayOfInts() {
    val ints = arrayOf(1, 2, 3)
    val checked: Array<Int> = ints
}

fun arrayOfStrings() {
    val strings = arrayOf("hello", "world")
    val checked: Array<String> = strings
}

fun arrayOfMixed() {
    val mixed = arrayOf(1, "two", 3.0)
    val checked: Array<Any> = mixed
}
