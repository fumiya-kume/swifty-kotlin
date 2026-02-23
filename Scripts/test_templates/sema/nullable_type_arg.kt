package golden.sema

fun useNullableArg() {
    val list: List<String?> = listOf("a", null, "b")
    val first: String? = list[0]
}
