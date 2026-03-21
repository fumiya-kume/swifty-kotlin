fun main() {
    println("-- compareBy then thenBy --")
    val nums1 = listOf(31, 24, 12, 22, 13, 21, 14)
    println(nums1.sortedBy { it % 10 }.sortedBy { it / 10 })

    println("-- thenByDescending --")
    println(nums1.sortedByDescending { it % 10 }.sortedBy { it / 10 })

    println("-- compareByDescending + thenBy --")
    println(nums1.sortedBy { it % 10 }.sortedByDescending { it / 10 })

    println("-- reversed --")
    println(nums1.sortedByDescending { it % 10 }.sortedByDescending { it / 10 })

    println("-- triple chain --")
    val nums2 = listOf(231, 114, 123, 212, 111, 223, 214)
    println(nums2.sortedBy { it % 10 }.sortedBy { (it / 10) % 10 }.sortedBy { it / 100 })

    println("-- integer sort --")
    val nums = listOf(3, 1, 4, 1, 5, 9, 2, 6)
    println(nums.sortedBy { it }.sortedBy { it % 3 })

    println("-- string length then alpha --")
    val words = listOf("fig", "cherry", "apple", "date", "banana", "fig")
    println(words.sorted().sortedBy { it.length })
}
