fun String?.isNullOrEmptyCompat(): Boolean = this == null || this.length == 0
fun String.tagCompat(): Int = 1
fun String?.tagCompat(): Int = 0

fun asInt(value: Boolean): Int = if (value) 1 else 0

fun main() {
    val nullValue: String? = null
    val emptyValue: String? = ""
    val textValue: String? = "x"

    println(asInt(nullValue.isNullOrEmptyCompat()))
    println(asInt(emptyValue.isNullOrEmptyCompat()))
    println(asInt(textValue.isNullOrEmptyCompat()))
    println(asInt(null.isNullOrEmptyCompat()))
    println("k".tagCompat())
    println(nullValue.tagCompat())
}
