// KSWIFTK_DIFF_IGNORE: TEST-NUM-017 — Int.toChar() does not mask to the low 16 bits.
// For code points outside 0..65535, kotlinc keeps only the low 16 bits (e.g.
// 65601.toChar().code == 65) but the native backend returns the untruncated value.
// See TODO.md (TEST-NUM-017).
fun main() {
    println(65601.toChar().code)
    println(70000.toChar().code)
    println(65536.toChar().code)
    println(131072.toChar().code)
}
