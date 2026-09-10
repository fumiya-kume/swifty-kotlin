// RF-FIXTURE-002: an argument-less arrayOf() takes its element type from the expected type.

fun arrayOfWithExpectedType() {
    val strings: Array<String> = arrayOf()
}
