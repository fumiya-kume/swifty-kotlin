package golden.sema

fun useAppendVarargStrings(): String {
    val sb = StringBuilder()
    sb.append("a", "b", "c")
    return sb.toString()
}

fun useAppendVarargAny(): String {
    val sb = StringBuilder()
    sb.append("hello", 42, true)
    return sb.toString()
}

fun useAppendVarargSpread(): String {
    val sb = StringBuilder()
    val parts = arrayOf("x", "y", "z")
    sb.append(*parts)
    return sb.toString()
}
