fun main() {
    val sourceList = listOf(1, 2, 2)
    val copiedList = sourceList.toMutableList()
    copiedList.add(3)
    println(sourceList)
    println(copiedList)

    val copiedSet = sourceList.toSet()
    println(copiedSet)
    println(copiedSet.contains(2))

    val sourceMap = mapOf("a" to 1)
    val copiedMap = sourceMap.toMutableMap()
    copiedMap["b"] = 2
    println(sourceMap)
    println(copiedMap)
}
