// BUG-231: Static non-null numeric values whose raw bits equal the null
// sentinel must retain their Kotlin hashCode; nullable nulls must stay zero.
fun main() {
    println(Long.MIN_VALUE.hashCode())
    println((-0.0).hashCode())
    println(9223372036854775808UL.hashCode())

    val nullableLong: Long? = null
    val nullableDouble: Double? = null
    val nullableULong: ULong? = null
    println(nullableLong.hashCode())
    println(nullableDouble.hashCode())
    println(nullableULong.hashCode())
}
