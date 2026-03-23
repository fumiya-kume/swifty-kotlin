fun main() {
    println("-- thenByDescending basic --")
    val words = listOf("banana", "cherry", "fig", "apple", "date", "bat")
    println(words.sortedByDescending { it }.sortedBy { it.length })

    println("-- thenByDescending selector --")
    val nums1 = listOf(130, 225, 330, 125, 230)
    println(nums1.sortedByDescending { it % 100 }.sortedBy { it / 100 })

    println("-- chained thenByDescending --")
    val nums2 = listOf(231, 114, 123, 212, 111, 223, 214)
    println(
        nums2
            .sortedByDescending { it % 10 }
            .sortedByDescending { (it / 10) % 10 }
            .sortedBy { it / 100 }
    )

    println("-- compareByDescending then thenByDescending --")
    println(nums1.sortedByDescending { it % 100 }.sortedByDescending { it / 100 })

    println("-- thenByDescending int selector --")
    val nums3 = listOf(31, 24, 12, 22, 13, 21, 14)
    println(nums3.sortedByDescending { it }.sortedBy { it / 10 })

    println("-- stability check --")
    val nums4 = listOf(3, 1, 4, 1, 5, 9, 2, 6, 5, 3)
    println(nums4.sortedByDescending { it }.sortedBy { it % 2 })

    println("-- single element --")
    val single = listOf("only")
    println(single.sortedByDescending { it }.sortedBy { it.length })

    println("-- empty list --")
    val empty = listOf<String>()
    println(empty)

    println("-- mix thenBy and thenByDescending --")
    val nums5 = listOf(231, 214, 223, 212, 111, 123, 114)
    println(
        nums5
            .sortedByDescending { it % 10 }
            .sortedBy { (it / 10) % 10 }
            .sortedBy { it / 100 }
    )
}
