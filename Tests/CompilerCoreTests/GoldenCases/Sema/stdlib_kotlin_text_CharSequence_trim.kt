package golden.sema

fun trims(source: CharSequence, predicate: (Char) -> Boolean) {
    val a: CharSequence = source.trim()
    val b: CharSequence = source.trim('x')
    val c: CharSequence = source.trim(predicate)
    val d: CharSequence = source.trimStart()
    val e: CharSequence = source.trimStart('x')
    val f: CharSequence = source.trimStart(predicate)
    val g: CharSequence = source.trimEnd()
    val h: CharSequence = source.trimEnd('x')
    val i: CharSequence = source.trimEnd(predicate)
}
