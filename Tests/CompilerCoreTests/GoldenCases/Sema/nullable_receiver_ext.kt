package golden.sema

fun String?.isNullOrEmpty(): Boolean = this == null || this!!.isEmpty()

fun useNullableReceiver() {
    val s: String? = null
    val result = s.isNullOrEmpty()
}
