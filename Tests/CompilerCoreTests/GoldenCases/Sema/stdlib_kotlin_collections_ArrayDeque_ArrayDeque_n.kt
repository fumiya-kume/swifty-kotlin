fun inspectArrayDeque(
    deque: ArrayDeque<Int>,
    values: Collection<Int>,
    destination: Array<Int?>
) {
    deque.add(1)
    deque.add(0, 2)
    deque.addAll(values)
    deque.addAll(1, values)
    deque.clear()
    deque.contains(1)
    deque.first()
    deque.firstOrNull()
    deque[0]
    deque.indexOf(1)
    deque.last()
    deque.lastIndexOf(1)
    deque.lastOrNull()
    deque.remove(1)
    deque.removeAll(values)
    deque.removeAt(0)
    deque.removeFirst()
    deque.removeFirstOrNull()
    deque.removeLast()
    deque.removeLastOrNull()
    deque.retainAll(values)
    deque.set(0, 3)
    deque.toArray()
    deque.toArray(destination)
}
