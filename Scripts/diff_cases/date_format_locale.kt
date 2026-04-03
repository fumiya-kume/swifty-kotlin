// SKIP-DIFF: locale-aware date format APIs are not available in kotlinc diff reference.
import java.text.getDateInstance
import java.text.getDateTimeInstance
import java.text.getTimeInstance
import java.text.ofPattern

fun main() {
    val custom = ofPattern("yyyy-MM-dd HH:mm z", "en_US", "Asia/Tokyo").format(0L)
    val dateOnly = getDateInstance("ja_JP").format(0L)
    val timeOnly = getTimeInstance("en_US", "UTC").format(0L)
    val dateTime = getDateTimeInstance("en_US", "Asia/Tokyo").format(0L)

    println(custom)
    println(dateOnly)
    println(timeOnly)
    println(dateTime)
}
