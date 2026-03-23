fun main() {
    val list: ArrayList<String> = ArrayList()
    list.add("hello")
    list.add("world")
    println(list.size)
    println(list[0])

    val ml: MutableList<String> = list
    ml.add("!")
    println(ml.size)

    val nums = ArrayList<Int>()
    nums.add(1)
    nums.add(2)
    nums.add(3)
    nums.removeAt(0)
    println(nums)

    val items: List<String> = ArrayList()
    println(items.size)
}
