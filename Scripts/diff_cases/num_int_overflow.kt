// SKIP-DIFF: SPEC-NUM-0001 — Int/Short/Byte arithmetic and shifts are computed
// at 64-bit width and never truncated to 32/16/8 bits, so signed overflow does
// not wrap around as Kotlin (and the JVM) require. Remove the SKIP-DIFF marker
// once Int width semantics are fixed in codegen.
//
// Expected (kotlinc) vs current kswiftk:
//   Int.MAX_VALUE + 1   -> -2147483648   (kswiftk: 2147483648)
//   Int.MAX_VALUE * 2   -> -2            (kswiftk: 4294967294)
//   -Int.MIN_VALUE      -> -2147483648   (kswiftk: 2147483648)
//   1 shl 31            -> -2147483648   (kswiftk: 2147483648)
//   1 shl 32            -> 1 (shift masked to 5 bits)  (kswiftk: 4294967296)
//   -1 ushr 1           -> 2147483647    (kswiftk: 9223372036854775807)
fun main() {
    println(Int.MAX_VALUE + 1)
    println(Int.MIN_VALUE - 1)
    println(-Int.MIN_VALUE)
    println(Int.MAX_VALUE * 2)
    println(100000 * 100000)
    println(1 shl 31)
    println(1 shl 32)
    println(-1 ushr 1)
    println(Int.MIN_VALUE ushr 31)
}
