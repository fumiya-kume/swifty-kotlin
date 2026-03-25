fun main() {
    // Basic array operations
    val arr = arrayOf(1, 2, 3, 4, 5)
    println(arr.size)
    println(arr[0])
    println(arr[4])

    // Array modification
    arr[0] = 99
    println(arr[0])

    // IntArray operations
    val intArr = intArrayOf(10, 20, 30)
    println(intArr.size)
    println(intArr[1])

    // Array element access and size
    val nums = arrayOf(100, 200, 300)
    println(nums.size)
    println(nums[2])
}
// SKIP-DIFF: array copy parity pending
