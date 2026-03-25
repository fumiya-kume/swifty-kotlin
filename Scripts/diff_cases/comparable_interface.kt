// STDLIB-COMP-041: Comparableインターフェース完全実装テストケース

// 基本的なComparable<T>インターフェースのテスト
fun basicComparableTest(): Int {
    val a = 10
    val b = 20
    
    // compareTo()メソッドのテスト
    val compareResult = a.compareTo(b)
    println("10.compareTo(20) = $compareResult")
    
    // 比較演算子のテスト（compareToへのdesugaring）
    val lessThan = a < b
    val greaterThan = a > b
    val lessOrEqual = a <= b
    val greaterOrEqual = a >= b
    
    println("10 < 20 = $lessThan")
    println("10 > 20 = $greaterThan")
    println("10 <= 20 = $lessOrEqual")
    println("10 >= 20 = $greaterOrEqual")
    
    return if (compareResult < 0 && lessThan && !greaterThan && lessOrEqual && !greaterOrEqual) 0 else 1
}

// ジェネリック型制約のテスト
fun <T : Comparable<T>> maxItem(a: T, b: T): T = if (a > b) a else b

fun <T : Comparable<T>> clamp(value: T, min: T, max: T): T = when {
    value < min -> min
    value > max -> max
    else -> value
}

fun genericConstraintsTest(): Int {
    // Int型でのテスト
    val intMax = maxItem(15, 25)
    println("maxItem(15, 25) = $intMax")
    
    val intClamped = clamp(30, 10, 20)
    println("clamp(30, 10, 20) = $intClamped")
    
    // String型でのテスト
    val stringMax = maxItem("apple", "banana")
    println("maxItem(\"apple\", \"banana\") = $stringMax")
    
    val stringClamped = clamp("zebra", "apple", "melon")
    println("clamp(\"zebra\", \"apple\", \"melon\") = $stringClamped")
    
    return if (intMax == 25 && intClamped == 20 && stringMax == "banana" && stringClamped == "melon") 0 else 1
}

// null安全な比較のテスト
fun nullSafeComparisonTest(): Int {
    val a: Int? = 10
    val b: Int? = 20
    val c: Int? = null
    
    // 通常の比較（nullを含む場合）
    try {
        // これはエラーになるべき（nullとの比較）
        val result1 = a?.compareTo(b) ?: 0
        println("a?.compareTo(b) = $result1")
        
        val result2 = a?.compareTo(c) ?: -1
        println("a?.compareTo(null) = $result2")
        
        val result3 = c?.compareTo(a) ?: 1
        println("null?.compareTo(a) = $result3")
        
    } catch (e: Exception) {
        println("Expected exception for null comparison: ${e.message}")
    }
    
    return 0
}

// プリミティブ型のComparable実装テスト
fun primitiveComparableTest(): Int {
    val intVal = 42
    val longVal = 42L
    val doubleVal = 42.0
    val floatVal = 42.0f
    val charVal = 'A'
    
    // 各プリミティブ型でのcompareToテスト
    println("Int compareTo: ${intVal.compareTo(30)}")
    println("Long compareTo: ${longVal.compareTo(30L)}")
    println("Double compareTo: ${doubleVal.compareTo(30.0)}")
    println("Float compareTo: ${floatVal.compareTo(30.0f)}")
    println("Char compareTo: ${charVal.compareTo('B')}")
    
    // 比較演算子のテスト
    val intCompare = intVal > 30
    val longCompare = longVal > 30L
    val doubleCompare = doubleVal > 30.0
    val floatCompare = floatVal > 30.0f
    val charCompare = charVal < 'B'
    
    println("Int > 30: $intCompare")
    println("Long > 30L: $longCompare")
    println("Double > 30.0: $doubleCompare")
    println("Float > 30.0f: $floatCompare")
    println("Char < 'B': $charCompare")
    
    return if (intCompare && longCompare && doubleCompare && floatCompare && charCompare) 0 else 1
}

// 複雑な型制約のテスト
data class Person(val name: String, val age: Int) : Comparable<Person> {
    override fun compareTo(other: Person): Int = this.age.compareTo(other.age)
}

fun complexTypeConstraintsTest(): Int {
    val person1 = Person("Alice", 25)
    val person2 = Person("Bob", 30)
    val person3 = Person("Charlie", 20)
    
    // Comparable<Person>の実装テスト
    val compareResult = person1.compareTo(person2)
    println("Person(\"Alice\", 25).compareTo(Person(\"Bob\", 30)) = $compareResult")
    
    // 比較演算子のテスト
    val isYounger = person1 < person2
    val isOlder = person1 > person3
    val sameAge = person1 <= person1
    
    println("Alice < Bob: $isYounger")
    println("Alice > Charlie: $isOlder")
    println("Alice <= Alice: $sameAge")
    
    // ジェネリック関数での使用
    val oldest = maxItem(person1, person2)
    val ageClamped = clamp(person3, person1, person2)
    
    println("Oldest person: ${oldest.name}")
    println("Clamped person: ${ageClamped.name}")
    
    return if (compareResult < 0 && isYounger && isOlder && sameAge && oldest.name == "Bob" && ageClamped.name == "Alice") 0 else 1
}

// バリアンス修飾子のテスト
fun varianceTest(): Int {
    // Comparable<in T>の反変性テスト
    fun compareStrings(a: String, b: String): Int = a.compareTo(b)
    
    val result = compareStrings("hello", "world")
    println("compareStrings(\"hello\", \"world\") = $result")
    
    // ジェネリックメソッドでのバリアンス
    fun <T> compareItems(items: List<T>, a: T, b: T) where T : Comparable<T> {
        println("Comparing $a and $b: ${a.compareTo(b)}")
        println("$a < $b: ${a < b}")
        println("$a > $b: ${a > b}")
    }
    
    compareItems(listOf("x", "y", "z"), "apple", "banana")
    compareItems(listOf(1, 2, 3), 10, 20)
    
    return 0
}

// メインテスト関数
fun main() {
    println("=== Comparable Interface Complete Implementation Test ===")
    
    println("\n1. Basic Comparable Test:")
    val basicResult = basicComparableTest()
    println("Result: $basicResult")
    
    println("\n2. Generic Constraints Test:")
    val genericResult = genericConstraintsTest()
    println("Result: $genericResult")
    
    println("\n3. Null-Safe Comparison Test:")
    val nullSafeResult = nullSafeComparisonTest()
    println("Result: $nullSafeResult")
    
    println("\n4. Primitive Comparable Test:")
    val primitiveResult = primitiveComparableTest()
    println("Result: $primitiveResult")
    
    println("\n5. Complex Type Constraints Test:")
    val complexResult = complexTypeConstraintsTest()
    println("Result: $complexResult")
    
    println("\n6. Variance Test:")
    val varianceResult = varianceTest()
    println("Result: $varianceResult")
    
    val totalResult = basicResult + genericResult + nullSafeResult + primitiveResult + complexResult + varianceResult
    println("\n=== Total Test Result: $totalResult ===")
    
    if (totalResult == 0) {
        println("✅ All Comparable interface tests passed!")
    } else {
        println("❌ Some tests failed!")
    }
}
