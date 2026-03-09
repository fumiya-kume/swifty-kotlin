fun main() {
    val defaultMargin = """
        |alpha
        |beta
        |gamma
    """.trimMargin()
    println(defaultMargin)

    val customMargin = """
        >left
        >right
    """.trimMargin(">")
    println(customMargin)
}
