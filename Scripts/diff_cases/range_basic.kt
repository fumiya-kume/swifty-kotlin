fun main() {
    // Constructor: start..end
    val r = 1..10

    // Properties: first, last, step
    println(r.first)
    println(r.last)
    println(r.step)

    // Properties: start, end (aliases for first, last)
    println(r.start)
    println(r.end)

    // Contains: in operator, contains(), isEmpty()
    println(5 in r)
    println(r.contains(5))
    println(r.contains(3))
    println(r.contains(11))
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

    // Test with step
    val r2 = 1..10 step 3
    println("Stepped range: ${r2.toList()}")
    println("Contains 4: ${r2.contains(4)}")
    println("Contains 7: ${r2.contains(7)}")
    println("Reversed stepped: ${r2.reversed().toList()}")

    // Test downTo
    val r3 = 10 downTo 1
    println("DownTo: ${r3.toList()}")
    println("Reversed downTo: ${r3.reversed().toList()}")
}
