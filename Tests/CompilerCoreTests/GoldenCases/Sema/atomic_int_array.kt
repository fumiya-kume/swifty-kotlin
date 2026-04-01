package golden.sema

import kotlin.concurrent.atomics.AtomicIntArray

fun main() {
    val fromSize = AtomicIntArray(3)
    val fromArray = AtomicIntArray(intArrayOf(1, 2, 3))
    val fromFactory = AtomicIntArray(3) { it + 1 }

    val size = fromSize.size
    val length = fromSize.length
    fromSize[0] = 7
    val first = fromSize[0]
    fromSize.loadAt(1)
    fromSize.storeAt(1, 8)
    fromSize.compareAndSetAt(1, 8, 9)
    fromSize.compareAndExchangeAt(1, 9, 10)
    fromSize.fetchAndAddAt(1, 2)
    fromSize.addAndFetchAt(1, 3)
    fromSize.fetchAndIncrementAt(1)
    fromSize.incrementAndFetchAt(1)
    fromSize.fetchAndDecrementAt(1)
    fromSize.decrementAndFetchAt(1)
    fromSize.fetchAndUpdateAt(1) { it + 1 }
    fromSize.updateAndFetchAt(1) { it + 1 }
    fromSize.updateAt(1) { it + 1 }
    fromArray[0]
    fromFactory.toString()

    println(size + length + first)
}
