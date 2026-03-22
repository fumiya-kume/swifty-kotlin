fun main() {
    val name = "World"
    val x = 42

    // Double-dollar: $ is literal, $$ triggers interpolation
    val s1 = $$"Hello $name, value = $${name}"
    println(s1)

    // Triple-dollar: $ and $$ are literal, $$$ triggers interpolation
    val s2 = $$$"Price is $$100, name = $$${name}"
    println(s2)

    // Expression interpolation
    val s3 = $$"Result: $${x + 1}"
    println(s3)

    // Raw string with multi-dollar
    val s4 = $$"""
        Dollar sign: $
        Interpolated: $${name}
    """.trimIndent()
    println(s4)

    // No interpolation when fewer dollars
    val s5 = $$"literal $x and $name"
    println(s5)
}
