package golden.sema

enum class Direction { NORTH, SOUTH }

fun compare(a: Direction, b: Direction): Int = a.compareTo(b)
fun equal(a: Direction, b: Any?): Boolean = a.equals(b)
fun hash(a: Direction): Int = a.hashCode()
fun name(a: Direction): String = a.name
fun ordinal(a: Direction): Int = a.ordinal
fun string(a: Direction): String = a.toString()
