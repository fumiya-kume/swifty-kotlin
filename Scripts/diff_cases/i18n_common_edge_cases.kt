import java.util.Locale

fun main() {
    println("%s:%d".format("age", 7))
    println("%.1f".format(3.5))

    println("Hello".uppercase())
    println("Hello".lowercase())

    val locale = Locale("en", "US")
    println(locale.language)
    println(locale.country)

    println("ff".toIntOrNull(16))
    println("xz".toIntOrNull(16))
}
