package golden.sema

import kotlin.concurrent.Volatile

class VolatileHolder {
    @Volatile
    var value: Int = 0
}

fun readVolatile(holder: VolatileHolder): Int = holder.value

fun main() {
    val holder = VolatileHolder()
    println(readVolatile(holder))
}
