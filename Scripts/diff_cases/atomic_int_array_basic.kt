import kotlin.concurrent.atomics.AtomicIntArray

fun main() {
    val fromSize = AtomicIntArray(3)
    val fromArray = AtomicIntArray(intArrayOf(1, 2, 3))
    val fromFactory = AtomicIntArray(3) { it + 1 }

    fromSize[0] = 7
    println(fromSize[0])
    println(fromSize.compareAndSetAt(0, 7, 8))
    println(fromSize.fetchAndAddAt(1, 2))
    println(fromSize.loadAt(1))
    println(fromArray.size)
    println(fromFactory.length)

    fromFactory.updateAt(1) { it + 4 }
    println(fromFactory)
}
