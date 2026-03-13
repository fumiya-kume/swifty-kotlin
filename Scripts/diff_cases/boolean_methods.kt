fun sideEffect(label: String, value: Boolean): Boolean {
    println(label)
    return value
}

fun main() {
    println(true.not())
    println(true.and(false))
    println(false.or(true))
    println(true.xor(true))
    println(true.xor(false))

    val nullableTrue: Boolean? = true
    val nullableNull: Boolean? = null
    println((nullableTrue?.not()) ?: true)
    println(nullableNull?.not() == null)
    println((nullableTrue?.and(false)) ?: true)
    println(nullableNull?.and(true) == null)
    println((nullableNull?.or(sideEffect("null rhs", true))) ?: false)

    println(true.and(sideEffect("and rhs", false)))
    println(false.or(sideEffect("or rhs", true)))
}
