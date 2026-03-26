fun main() {
    // compareValues with non-null values
    println(compareValues(1, 2))
    println(compareValues(3, 3))
    println(compareValues(5, 1))

    // compareValues with null values
    println(compareValues(null, 1))
    println(compareValues(1, null))
    val a: Int? = null
    val b: Int? = null
    println(compareValues(a, b))

    // compareValuesBy with single selector
    println(compareValuesBy(10, 20, { x: Int -> x }))
    println(compareValuesBy(5, 5, { x: Int -> x }))
    println(compareValuesBy(30, 10, { x: Int -> x }))
}
