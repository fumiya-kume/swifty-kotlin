// STDLIB-HOF-029: 関数型完全実装テストケース（シンプル版）

// 基本的な関数型の使用
fun testBasicFunctionTypes() {
    val f0: () -> Int = { 42 }
    val f1: (String) -> Int = { it.length }
    val f2: (Int, String) -> String = { num, str -> "$num-$str" }
    
    println(f0())
    println(f1("hello"))
    println(f2(123, "test"))
}

// 関数型の変位指定テスト
fun testFunctionVariance() {
    val stringProducer: () -> String = { "hello" }
    val anyProducer: () -> Any = stringProducer
    
    val anyConsumer: (Any) -> Unit = { println(it) }
    val stringConsumer: (String) -> Unit = anyConsumer
    
    println(anyProducer())
    stringConsumer("test")
}

// 高階関数での関数型使用
fun testHigherOrderFunctions() {
    val numbers = listOf(1, 2, 3, 4, 5)
    
    val mapper: (Int) -> String = { "Number: $it" }
    val mapped = numbers.map(mapper)
    println(mapped)
}

fun main() {
    testBasicFunctionTypes()
    testFunctionVariance()
    testHigherOrderFunctions()
}
