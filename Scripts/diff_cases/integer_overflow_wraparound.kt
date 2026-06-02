// KSWIFTK_DIFF_IGNORE: TEST-NUM-017 — Int/Long arithmetic does not wrap at 32/64-bit.
// The native backend represents all integers as i64 and never truncates Int (32-bit)
// results, so e.g. Int.MAX_VALUE + 1 yields 2147483648 instead of -2147483648.
// See TODO.md (TEST-NUM-017). Enable this case once 32-bit wraparound is implemented.
fun main() {
    var imax = Int.MAX_VALUE
    var imin = Int.MIN_VALUE
    println(imax + 1)
    println(imin - 1)
    println(imax * 2)
    println(imax + imax)
    var negOne = -1
    println(imin / negOne)
    println(imin % negOne)
    println(Int.MAX_VALUE + 1)
    var d = 100000
    println(d * d)
    var lmax = Long.MAX_VALUE
    var lmin = Long.MIN_VALUE
    println(lmax + 1L)
    println(lmin - 1L)
    println(-imin)
    println(-lmin)
}
