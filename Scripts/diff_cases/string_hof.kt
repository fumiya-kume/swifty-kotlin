fun main() {
    val s = "Hello, World!"
    println(s.filter { it.isUpperCase() })
    println(s.map { it.uppercase() })
    println(s.count { it == 'l' })
    println(s.any { it.isDigit() })
    println(s.all { it.isLetter() })
    println(s.none { it.isDigit() })
    println("abc".reversed())
    println("hello".padStart(10))
    println("hello".padStart(10, '*'))
    println("hello".padEnd(10, '-'))
    println("Hello".equals("hello", ignoreCase = true))
    println("Hello".equals("hello", ignoreCase = false))
    
    // STDLIB-HOF-023: Advanced String Higher-Order Functions
    println("\n=== Advanced String HOF ===")
    
    // mapIndexed
    val mappedIndexed = s.mapIndexed { index, char -> "$index:$char" }
    println("mapIndexed: $mappedIndexed")
    
    // mapNotNull
    val mapNotNullResult = s.mapNotNull { char -> 
        if (char.isUpperCase()) char.uppercase() else null 
    }
    println("mapNotNull: $mapNotNullResult")
    
    // filterIndexed
    val filterIndexedResult = s.filterIndexed { index, char -> index % 2 == 0 && char.isLetter() }
    println("filterIndexed: $filterIndexedResult")
    
    // filterNot
    val filterNotResult = s.filterNot { it.isUpperCase() }
    println("filterNot: $filterNotResult")
    
    // takeWhile
    val takeWhileResult = s.takeWhile { it != ',' }
    println("takeWhile: $takeWhileResult")
    
    // dropWhile
    val dropWhileResult = s.dropWhile { it != ',' }
    println("dropWhile: $dropWhileResult")
    
    // splitToSequence
    val splitSequence = "a,b,c,d".splitToSequence(",")
    println("splitToSequence: ${splitSequence.toList()}")
    
    // joinToString
    val joinResult = listOf("apple", "banana", "cherry").joinToString(", ", "[", "]")
    println("joinToString: $joinResult")
    
    // find
    val findResult = s.find { it.isUpperCase() }
    println("find: $findResult")
    
    // findLast
    val findLastResult = s.findLast { it.isLetter() }
    println("findLast: $findLastResult")
}
