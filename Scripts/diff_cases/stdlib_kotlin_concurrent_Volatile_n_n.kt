import kotlin.concurrent.Volatile

class VolatileHolder {
    @Volatile
    var value: Int = 0
}

fun main() {
    val holder = VolatileHolder()
    println(holder.value)
}
