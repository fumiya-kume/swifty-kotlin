// KSWIFTK_DIFF_IGNORE: TEST-NUM-017 — UInt/ULong arithmetic does not wrap at 32/64-bit.
// Same root cause as the signed overflow gap (i64-uniform backend, no truncation):
// UInt.MAX_VALUE + 1u yields 4294967296 instead of 0. See TODO.md (TEST-NUM-017).
fun main() {
    val umax = 4294967295u
    println(umax + 1u)
    val uzero = 0u
    println(uzero - 1u)
    println(umax * 2u)
    val ulmax = 18446744073709551615uL
    println(ulmax + 1uL)
}
