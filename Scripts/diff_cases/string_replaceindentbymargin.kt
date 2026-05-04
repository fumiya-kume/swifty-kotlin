fun marker(value: String) {
    println(value.replace("\n", "/"))
}

fun main() {
    marker("\n    |alpha\n    |  beta\n    gamma\n".replaceIndentByMargin("> ", "|"))
    marker("\n    |alpha\n    |\n    |beta\n".replaceIndentByMargin("--", "|"))
    marker("  >left\n    >right".replaceIndentByMargin("--", ">"))
    marker("|alpha\n|beta".replaceIndentByMargin())
    marker("|alpha\n|beta".replaceIndentByMargin(">>"))
    marker("plain\n  |mark".replaceIndentByMargin("++", "|"))
}
