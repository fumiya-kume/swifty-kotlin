package golden.sema

fun String?.isNullOrEmptyCompat(): Boolean = this == null || this.length == 0
fun <T> T?.isPresentCompat(): Boolean = this != null
fun String.tagCompat(): Int = 1
fun String?.tagCompat(): Int = 0

fun useNullableReceiver() {
    val s: String? = null
    val fromNullable = s.isNullOrEmptyCompat()
    val fromNullLiteral = null.isNullOrEmptyCompat()
    val genericFromNullable = s.isPresentCompat()
    val genericFromNullLiteral = null.isPresentCompat<String>()
    val genericFromNonNull = "abc".isPresentCompat()
    val nonNullPreferred = "abc".tagCompat()
    val nullableFallback = s.tagCompat()
}
