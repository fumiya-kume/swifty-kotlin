// KSWIFTK_DIFF_IGNORE: TEST-NUM-017 — Int/Long shifts do not mask the shift amount
// (Int: & 31, Long: & 63) and Int shift results are not truncated to 32 bits.
// Out-of-range or negative shift amounts are emitted as raw LLVM shifts (undefined
// behavior), producing garbage or null. See TODO.md (TEST-NUM-017).
fun main() {
    var one = 1
    println(one shl 32)
    println(one shl 33)
    println(one shl 31)
    println(one shl 30)
    var neg = Int.MIN_VALUE
    println(neg shr 1)
    println(neg ushr 1)
    println(neg shr 32)
    println(neg ushr 32)
    println(one shl -1)
    println(1 shl 32)
    println(-1 ushr 1)
    var lone = 1L
    println(lone shl 64)
    println(lone shl 65)
    var lneg = Long.MIN_VALUE
    println(lneg shr 64)
}
