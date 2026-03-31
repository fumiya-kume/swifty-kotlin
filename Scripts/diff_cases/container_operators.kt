class Cursor(private val values: MutableList<Int>) {
    private var index = 0

    operator fun hasNext(): Boolean = index < values.size
    operator fun next(): Int = values[index++]
}

class Bucket(private val values: MutableList<Int>) {
    operator fun get(index: Int): Int = values[index]

    operator fun set(index: Int, value: Int) {
        values[index] = value
    }

    operator fun contains(value: Int): Boolean = values.any { it == value }
    operator fun iterator(): Cursor = Cursor(values)
    operator fun rangeTo(other: Bucket): Int = values.size + other.values.size
}

fun joinAll(vararg values: Int): String = values.joinToString(",")

fun main() {
    val left = Bucket(mutableListOf(1, 2, 3))
    val right = Bucket(mutableListOf(4, 5))

    println(left[1])
    left[1] = 20
    println(left[1])

    println(20 in left)
    println(9 !in left)

    var total = 0
    for (value in left) {
        total += value
    }
    println(total)

    println(left..right)

    val spread = intArrayOf(7, 8, 9)
    println(joinAll(1, *spread, 10))
}
