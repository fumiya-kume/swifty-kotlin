fun tripleCreate(): Triple<Int, String, Boolean> = Triple(1, "a", true)
fun tripleFirst(): Int = Triple(1, "a", true).first
fun tripleSecond(): String = Triple(1, "a", true).second
fun tripleThird(): Boolean = Triple(1, "a", true).third
fun tripleToString(): String = Triple(1, "a", true).toString()
