package golden.sema

fun throwOrValue(flag: Boolean): String {
    val x: String = if (flag) "ok" else throw IllegalArgumentException("fail")
    return x
}

fun returnOrValue(flag: Boolean): Int {
    val y: Int = if (flag) 42 else return -1
    return y
}
