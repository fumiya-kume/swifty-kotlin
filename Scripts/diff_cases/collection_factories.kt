fun main() {
    // listOf
    val list = listOf(1, 2, 3)
    println(list)
    println(list.size)

    // listOfNotNull
    println(listOfNotNull(1, null, 2, null, 3))
    println(listOfNotNull<Int>(null, null))

    // emptyList
    println(emptyList<Int>())
    println(emptyList<String>().size)

    // setOf
    val set = setOf(1, 2, 2, 3)
    println(set.size)
    println(set.contains(2))

    // emptySet
    println(emptySet<Int>().isEmpty())

    // mutableSetOf
    val mset = mutableSetOf(10, 20)
    mset.add(30)
    println(mset.size)

    // mapOf
    val map = mapOf("a" to 1, "b" to 2)
    println(map.size)
    println(map["a"])

    // emptyMap
    println(emptyMap<String, Int>().isEmpty())

    // mutableMapOf
    val mmap = mutableMapOf("x" to 100)
    mmap["y"] = 200
    println(mmap.size)

    // range to list
    val rangeList = (1..5).toList()
    println(rangeList)

    // char range to list
    val charList = ('a'..'e').toList()
    println(charList)

    // arrayOf().toList()
    val arr = arrayOf(7, 8, 9)
    val fromArr = arr.toList()
    println(fromArr)

    // list.toTypedArray()
    val backToArr = list.toTypedArray()
    println(backToArr.size)
    println(backToArr[0])
}
