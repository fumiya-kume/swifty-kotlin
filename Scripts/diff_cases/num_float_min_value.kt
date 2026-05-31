// SKIP-DIFF: SPEC-NUM-0006 — Double.MIN_VALUE / Float.MIN_VALUE shortest decimal
// representation differs from java.lang.Double/Float.toString. Swift's
// String(describing:) yields the truly shortest round-trippable form, while Java
// emits a different (also valid) shortest form for these subnormal extremes:
//   Double.MIN_VALUE -> Kotlin "4.9E-324"  ; kswiftk "5.0E-324"
//   Float.MIN_VALUE  -> Kotlin "1.4E-45"   ; kswiftk "1.0E-45"
// Matching Java's FloatingDecimal exactly for subnormals is out of scope for now.
fun main() {
    println(Double.MIN_VALUE)
    println(Float.MIN_VALUE)
}
