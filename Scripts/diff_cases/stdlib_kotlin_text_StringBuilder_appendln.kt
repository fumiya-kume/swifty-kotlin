@file:Suppress("DEPRECATION_ERROR")

fun main() {
    val builder = StringBuilder()
    val nullableAny: Any? = null
    val nullableString: String? = null

    println("noarg=${builder.appendln() === builder}")
    println("any=${builder.appendln(nullableAny) === builder}")
    println("boolean=${builder.appendln(true) === builder}")
    println("byte=${builder.appendln((-2).toByte()) === builder}")
    println("double=${builder.appendln(1.25) === builder}")
    println("float=${builder.appendln(2.5f) === builder}")
    println("int=${builder.appendln(3) === builder}")
    println("long=${builder.appendln(4L) === builder}")
    println("short=${builder.appendln(5.toShort()) === builder}")
    println("string=${builder.appendln(nullableString) === builder}")
    println("content=${builder.toString().replace("\n", "<NL>")}")
}
