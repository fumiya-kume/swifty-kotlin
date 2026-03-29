// STDLIB-GEN-059: ジェネリック型推論テストケース

// 基本的な変数宣言での型推論
fun testVariableTypeInference() {
    val list = listOf(1, 2, 3)
    val strList = listOf("hello", "world")
    println(list.size)
    println(strList.size)
}

// mapOf での型推論
fun testMapTypeInference() {
    val map = mapOf("key" to "value", "name" to "kotlin")
    val numMap = mapOf("one" to 1, "two" to 2, "three" to 3)
    println(map.size)
    println(numMap.size)
}

// ジェネリック関数の型推論
fun <T> identity(value: T): T = value

fun testGenericFunctionInference() {
    val str = identity("hello")
    val num = identity(42)
    val bool = identity(true)
    println(str)
    println(num)
    println(bool)
}

// 明示的な型指定との組み合わせ
fun testExplicitTypeWithInference() {
    val list: List<Int> = listOf(1, 2, 3)
    val map: Map<String, Int> = mapOf("a" to 1, "b" to 2)
    println(list.size)
    println(map.size)
}

fun main() {
    testVariableTypeInference()
    testMapTypeInference()
    testGenericFunctionInference()
    testExplicitTypeWithInference()
}
