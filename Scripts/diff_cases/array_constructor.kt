fun main() {
    val arr = Array(3) { it * 2 }
    println(arr[0])
    println(arr[1])
    println(arr[2])
    println(arr.size)

    // an explicit type argument wins over the expected type
    val explicitTypeArg: Array<out Any> = Array<Int>(3) { it }
    println(explicitTypeArg[0])
    println(explicitTypeArg[2])
    println(explicitTypeArg.size)

    // without a type argument the expected type supplies the element type
    val fromExpectedType: Array<String> = Array(3) { "x" }
    println(fromExpectedType[0])
    println(fromExpectedType[2])
    println(fromExpectedType.size)

    // the init lambda's index must still reach the body on both paths above
    val indexedFromExpectedType: Array<Int> = Array(3) { it + 10 }
    println(indexedFromExpectedType[0])
    println(indexedFromExpectedType[2])
    val indexedFromTypeArg = Array<Int>(3) { it + 20 }
    println(indexedFromTypeArg[0])
    println(indexedFromTypeArg[2])
}
