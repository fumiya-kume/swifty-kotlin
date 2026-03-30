fun main() {
    // Constructor: start..end
    val r = 1..10

    // Properties: first, last, step
    println(r.first)
    println(r.last)
    println(r.step)

    // Contains: in operator, contains(), isEmpty()
    println(5 in r)
    println(r.contains(5))
    println(r.isEmpty())
    println((5..1).isEmpty())

    // Converting: toList(), toIntArray()
    println(r.toList())
    val arr = r.toIntArray()
    println(arr.size)
    println(arr[0])
    println(arr[9])

    // Reversed
    println(r.reversed().toList())

    // For loop iteration
    var sum = 0
    for (i in 1..5) {
        sum += i
    }
    println(sum)
}
