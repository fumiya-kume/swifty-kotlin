package golden.sema

fun useOnEach(): String {
    val result = mutableListOf<Char>()
    return "hello".onEach { c -> result.add(c) }
}
