fun main() {
    // Test emptyArray()
    val empty = emptyArray<Int>()
    println("empty.size: ${empty.size}")
    println("empty.isEmpty(): ${empty.isEmpty()}")
    
    // Test arrayOf()
    val arr1 = arrayOf(1, 2, 3)
    val arr2 = arrayOf(1, 2, 3)
    val arr3 = arrayOf(1, 2, 4)
    
    // Test contentEquals()
    println("arr1.contentEquals(arr2): ${arr1.contentEquals(arr2)}")
    println("arr1.contentEquals(arr3): ${arr1.contentEquals(arr3)}")
    
    // Test contentHashCode()
    println("arr1.contentHashCode(): ${arr1.contentHashCode()}")
    println("arr2.contentHashCode(): ${arr2.contentHashCode()}")
    println("arr3.contentHashCode(): ${arr3.contentHashCode()}")
    
    // Test toMutableList()
    val mutableList = arr1.toMutableList()
    mutableList.add(4)
    println("mutableList after add: ${mutableList}")
    println("original arr1 unchanged: ${arr1.toList()}")
    
    // Test toTypedArray() from List
    val list = listOf(5, 6, 7)
    val typedArray = list.toTypedArray()
    println("typedArray from list: ${typedArray.toList()}")
}
// SKIP-DIFF: array factory parity pending
