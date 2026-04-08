// SKIP-DIFF: locale-aware and parse APIs may differ between KSwiftK and kotlinc reference.
import java.text.ofPattern

fun main() {
    // SimpleDateFormat-style: pattern only (default locale, UTC-fixed internally)
    val fmt = ofPattern("yyyy-MM-dd", "en_US", "UTC")
    val formatted = fmt.format(0L)
    println(formatted)

    // Round-trip: format then parse back
    val fmt2 = ofPattern("yyyy-MM-dd HH:mm:ss", "en_US", "UTC")
    val dateString = fmt2.format(0L)
    println(dateString)

    // Parse epoch millis back from formatted string
    val parsed = fmt2.parse(dateString)
    println(parsed)
}
