package golden.sema

fun bitwiseAnd(a: Int, b: Int): Int = a and b
fun bitwiseOr(a: Int, b: Int): Int = a or b
fun bitwiseXor(a: Int, b: Int): Int = a xor b
fun bitwiseInv(a: Int): Int = a.inv()
fun shiftLeft(a: Int, n: Int): Int = a shl n
fun shiftRight(a: Int, n: Int): Int = a shr n
fun unsignedShiftRight(a: Int, n: Int): Int = a ushr n
