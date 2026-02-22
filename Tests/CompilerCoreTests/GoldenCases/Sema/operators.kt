fun typeCheck(v: Any): Boolean = v is String

fun negatedTypeCheck(v: Any): Boolean = v !is Int

fun unsafeCast(v: Any): String = v as String

fun safeCast(v: Any): String? = v as? String

fun elvisOp(v: String?): String = v ?: "default"

fun nullAssertOp(v: String?): String = v!!

fun compoundAdd(x: Int): Int {
    var a = x
    a += 10
    return a
}

fun compoundSub(x: Int): Int {
    var b = x
    b -= 5
    return b
}

fun compoundMul(x: Int): Int {
    var c = x
    c *= 2
    return c
}

fun compoundDiv(x: Int): Int {
    var d = x
    d /= 3
    return d
}

fun compoundMod(x: Int): Int {
    var e = x
    e %= 4
    return e
}
