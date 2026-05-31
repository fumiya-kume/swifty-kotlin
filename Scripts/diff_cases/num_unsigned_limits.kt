// SKIP-DIFF: SPEC-NUM-0007 — Unsigned companion constants and several unsigned
// conversions/parsers are unresolved at compile time in kswiftk:
//   UInt/ULong/UByte/UShort.MAX_VALUE / MIN_VALUE  (KSWIFTK-SEMA-0024)
//   UInt.toByte(), String.toUByteOrNull(), ...
// Remove SKIP-DIFF once these unsigned stdlib members are wired.
fun main() {
    println(UInt.MAX_VALUE)
    println(UInt.MIN_VALUE)
    println(ULong.MAX_VALUE)
    println(ULong.MIN_VALUE)
    println(UByte.MAX_VALUE)
    println(UShort.MAX_VALUE)
    println(255u.toByte())
    println("255".toUByteOrNull())
    println("256".toUByteOrNull())
}
