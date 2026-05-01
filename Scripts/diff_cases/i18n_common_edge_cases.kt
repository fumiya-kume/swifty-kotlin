import java.util.Locale
import kotlin.text.CharDirectionality

fun main() {
    println("%s:%d".format("age", 7))
    println("%.1f".format(3.5))
    println(String.format(Locale("de", "DE"), "%.1f", 3.5))

    println("Hello".uppercase())
    println("Hello".lowercase())

    val locale = Locale("en", "US")
    println(locale.language)
    println(locale.country)

    println("ff".toIntOrNull(16))
    println("xz".toIntOrNull(16))
    println('A'.directionality == CharDirectionality.LEFT_TO_RIGHT)
    println('\u05D0'.directionality == CharDirectionality.RIGHT_TO_LEFT)
    println('5'.directionality == CharDirectionality.EUROPEAN_NUMBER)
    println(' '.directionality == CharDirectionality.WHITESPACE)
    val turkish = Locale("tr", "TR")
    println('I'.lowercase(turkish))
}
