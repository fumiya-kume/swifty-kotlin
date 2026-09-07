fun main() {
    val deque = ArrayDeque<Int>()
    println(deque.isEmpty())
    println(deque.add(1))
    deque.add(1, 2)
    deque.add(0, 0)
    deque.add(deque.size, 3)
    println(deque)

    println(deque.addAll(listOf(7, 8)))
    println(deque.addAll(2, listOf(4, 5)))
    println(deque)
    println(deque.contains(5))
    println(deque.contains(9))
    println(5 in deque)
    println(9 !in deque)
    println(deque.indexOf(7))
    deque.addLast(7)
    println(deque.lastIndexOf(7))

    println(deque.remove(4))
    println(deque.remove(9))
    println(deque.removeAt(0))
    println(deque.removeAt(deque.size - 1))
    println(deque.set(1, 40))
    println(deque.set(1, 41))
    deque[1] = 42
    println(deque[1])
    println(deque)
    println(deque.removeAll(listOf(40, 7)))
    println(deque)
    println(deque.retainAll(listOf(2, 3, 8)))
    println(deque)

    val array = deque.toArray()
    println(array.size)
    println(array[0])
    println(array[array.size - 1])

    val destination = arrayOfNulls<Int?>(5)
    destination[0] = 99
    destination[1] = 98
    destination[2] = 97
    destination[3] = 96
    destination[4] = 95
    val returned = deque.toArray(destination)
    println(returned === destination)
    println(destination[0])
    println(destination[deque.size])

    val smallDestination = arrayOfNulls<Int?>(1)
    val smallResult = deque.toArray(smallDestination)
    println(smallResult === smallDestination)
    println(smallResult.size)
    println(smallResult[0])

    try {
        deque.add(-1, 0)
    } catch (e: IndexOutOfBoundsException) {
        println(e.message)
    }
    try {
        deque.removeAt(deque.size)
    } catch (e: IndexOutOfBoundsException) {
        println(e.message)
    }

    val wrapped = ArrayDeque<Int>()
    var wrappedIndex = 0
    while (wrappedIndex < 8) {
        wrapped.addLast(wrappedIndex)
        wrappedIndex += 1
    }
    wrappedIndex = 0
    while (wrappedIndex < 3) {
        wrapped.removeFirst()
        wrappedIndex += 1
    }
    wrappedIndex = 8
    while (wrappedIndex < 11) {
        wrapped.addLast(wrappedIndex)
        wrappedIndex += 1
    }
    wrapped.add(2, 99)
    println(wrapped)
    println(wrapped.removeAt(4))
    println(wrapped)

    val nullable = ArrayDeque<String?>()
    nullable.add(null)
    nullable.addLast("value")
    println(nullable.contains(null))
    println(nullable.indexOf(null))
    println(nullable.toArray()[0])

    deque.clear()
    println(deque.isEmpty())
    println(deque.removeFirstOrNull())
    println(deque.removeLastOrNull())
}
