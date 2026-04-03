import java.util.Locale

fun main() {
    val byId = Locale("en_US_POSIX")
    val byParts = Locale("en", "US")

    println(byId.language)
    println(byId.country)
    println(byId.variant)
    println(byId.displayLanguage.length > 0)

    val original = Locale.getDefault()
    Locale.setDefault(Locale("ja", "JP"))
    println(Locale.getDefault().language)
    Locale.setDefault(original)

    println(byParts == Locale("en_US"))
    println(byParts.hashCode() == Locale("en", "US").hashCode())

    val locales = Locale.getAvailableLocales()
    println(locales.size > 0)
    println(locales[0].language.length >= 0)
}
