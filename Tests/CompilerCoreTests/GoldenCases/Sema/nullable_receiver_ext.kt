package golden.sema

fun String?.isNullOrEmptyCompat(): Boolean = this == null || this.length == 0
fun String.tagCompat(): Int = 1
fun String?.tagCompat(): Int = 0

fun useNullableReceiver() {
    val s: String? = null
    val fromNullable = s.isNullOrEmptyCompat()
    val fromNullLiteral = null.isNullOrEmptyCompat()
    val nonNullPreferred = "abc".tagCompat()
    val nullableFallback = s.tagCompat()
}
