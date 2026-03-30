// STDLIB-NUM-130: Floating-point precision complete implementation
// Tests: isNaN, isInfinite, isFinite, ulp, nextUp, nextDown, toBits, toRawBits, fromBits

fun main() {
    // isNaN
    println(Double.NaN.isNaN())                    // true
    println(1.0.isNaN())                           // false
    println(Float.NaN.isNaN())                     // true
    println(1.0f.isNaN())                          // false

    // isInfinite
    println(Double.POSITIVE_INFINITY.isInfinite()) // true
    println(Double.NEGATIVE_INFINITY.isInfinite()) // true
    println(1.0.isInfinite())                      // false
    println(Float.POSITIVE_INFINITY.isInfinite())  // true
    println(1.0f.isInfinite())                     // false

    // isFinite
    println(1.0.isFinite())                        // true
    println(Double.POSITIVE_INFINITY.isFinite())   // false
    println(Double.NaN.isFinite())                 // false
    println(1.0f.isFinite())                       // true
    println(Float.POSITIVE_INFINITY.isFinite())    // false

    // toBits / toRawBits
    val bits = 1.0.toBits()
    println(bits == 4607182418800017408L)          // true (IEEE 754 bits for 1.0)
    val rawBits = 1.0.toRawBits()
    println(rawBits == 4607182418800017408L)       // true

    val floatBits = 1.0f.toBits()
    println(floatBits == 1065353216)              // true (IEEE 754 bits for 1.0f)
    val floatRawBits = 1.0f.toRawBits()
    println(floatRawBits == 1065353216)           // true

    // fromBits round-trip: Double.fromBits(1.0.toBits()) == 1.0
    println(Double.fromBits(1.0.toBits()) == 1.0)  // true
    println(Float.fromBits(1.0f.toBits()) == 1.0f) // true

    // ulp (unit of least precision)
    val ulpVal = 1.0.ulp
    println(ulpVal > 0.0)                         // true
    println(ulpVal < 1.0)                         // true

    // nextUp / nextDown
    println(1.0.nextUp() > 1.0)                   // true
    println(1.0.nextDown() < 1.0)                 // true
}
