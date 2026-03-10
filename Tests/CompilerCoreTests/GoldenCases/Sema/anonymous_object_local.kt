package golden.sema

fun useAnonymousObjectLocal(): Int {
    val local = object {
        val value = 7
    }
    return local.value
}
