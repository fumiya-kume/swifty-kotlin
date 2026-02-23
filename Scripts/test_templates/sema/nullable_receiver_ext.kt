package golden.sema

fun String?.isNullOrBlank(): Boolean = this == null || this.length == 0

fun useNullableReceiver() {
    val s: String? = null
    val result = s.isNullOrBlank()
}
