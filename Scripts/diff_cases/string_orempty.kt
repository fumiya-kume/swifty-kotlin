fun main() {
    val nullStr: String? = null
    val emptyStr: String? = ""
    val nonEmptyStr: String? = "hello"

    // orEmpty on null returns ""
    println(nullStr.orEmpty())
    println(nullStr.orEmpty().length)

    // orEmpty on empty string returns ""
    println(emptyStr.orEmpty())
    println(emptyStr.orEmpty().length)

    // orEmpty on non-empty string returns the string itself
    println(nonEmptyStr.orEmpty())
    println(nonEmptyStr.orEmpty().length)

    // orEmpty chained with other string operations
    println(nullStr.orEmpty().isEmpty())
    println(nonEmptyStr.orEmpty().isEmpty())

    // orEmpty on literal null
    val result: String = (null as String?).orEmpty()
    println(result)
    println(result.length)

    // orEmpty on non-null String? assigned from non-null value
    val definitelyNotNull: String? = "world"
    println(definitelyNotNull.orEmpty())
}
