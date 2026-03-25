fun main() {
    // Comprehensive chunked(size, step) and transform tests
    
    println("=== Basic chunked(size) tests ===")
    
    val list = listOf(1, 2, 3, 4, 5, 6, 7)

    // chunked(size) — basic
    println(list.chunked(3))
    println(list.chunked(2))
    println(list.chunked(1))
    println(list.chunked(10))

    // String.chunked (no transform)
    println("abcdefg".chunked(3))
    println("abcdefg".chunked(2))
    
    println("\n=== chunked(size, step) tests ===")
    
    // chunked with step parameter
    val numbers = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    
    // step < size (overlapping chunks)
    println("step 2, size 4: ${numbers.chunked(4, 2)}")
    println("step 1, size 3: ${numbers.chunked(3, 1)}")
    
    // step == size (non-overlapping)
    println("step 3, size 3: ${numbers.chunked(3, 3)}")
    println("step 2, size 2: ${numbers.chunked(2, 2)}")
    
    // step > size (gaps between chunks)
    println("step 4, size 2: ${numbers.chunked(2, 4)}")
    println("step 5, size 3: ${numbers.chunked(3, 5)}")
    
    println("\n=== chunked with transform function ===")
    
    // chunked(size, transform)
    val transformed = list.chunked(3) { chunk ->
        chunk.sum()
    }
    println("chunked(3) sum: $transformed")
    
    val strings = listOf("hello", "world", "kotlin", "test")
    val stringTransformed = strings.chunked(2) { chunk ->
        chunk.joinToString("-")
    }
    println("chunked(2) join: $stringTransformed")
    
    println("\n=== chunked(size, step, transform) tests ===")
    
    // Combine all three parameters
    val complex = numbers.chunked(3, 2) { chunk ->
        "chunk(${chunk.joinToString()})=${chunk.average()}"
    }
    println("complex chunked: $complex")
    
    // Different step with transform
    val stepTransform = numbers.chunked(2, 3) { chunk ->
        chunk.map { it * it }
    }
    println("step transform: $stepTransform")
    
    println("\n=== String chunked with step ===")
    
    val text = "abcdefghijklmnopqrstuvwxyz"
    
    // String chunked with step
    println("text.chunked(3, 2): ${text.chunked(3, 2)}")
    println("text.chunked(4, 1): ${text.chunked(4, 1)}")
    println("text.chunked(5, 5): ${text.chunked(5, 5)}")
    println("text.chunked(2, 4): ${text.chunked(2, 4)}")
    
    // String chunked with step and transform
    val stringComplex = text.chunked(3, 2) { chunk ->
        chunk.uppercase()
    }
    println("string complex: $stringComplex")
    
    println("\n=== Edge cases ===")
    
    // Empty collections
    println("emptyList.chunked(3): ${emptyList<Int>().chunked(3)}")
    println("emptyList.chunked(3, 2): ${emptyList<Int>().chunked(3, 2)}")
    println("\"\".chunked(3): ${"".chunked(3)}")
    
    // Single element
    val single = listOf(42)
    println("single.chunked(1): ${single.chunked(1)}")
    println("single.chunked(2): ${single.chunked(2)}")
    println("single.chunked(1, 1): ${single.chunked(1, 1)}")
    println("single.chunked(1, 2): ${single.chunked(1, 2)}")
    
    // Size larger than collection
    val small = listOf(1, 2, 3)
    println("small.chunked(5): ${small.chunked(5)}")
    println("small.chunked(5, 3): ${small.chunked(5, 3)}")
    
    // Step = 1 (maximum overlap)
    println("numbers.chunked(3, 1): ${numbers.chunked(3, 1)}")
    
    println("\n=== Type-specific tests ===")
    
    // Double list
    val doubles = listOf(1.1, 2.2, 3.3, 4.4, 5.5)
    println("doubles.chunked(2): ${doubles.chunked(2)}")
    println("doubles.chunked(2, 1): ${doubles.chunked(2, 1)}")
    
    // Character list
    val chars = listOf('a', 'b', 'c', 'd', 'e', 'f')
    println("chars.chunked(2): ${chars.chunked(2)}")
    println("chars.chunked(3, 2): ${chars.chunked(3, 2)}")
    
    // Boolean list
    val booleans = listOf(true, false, true, false, true)
    println("booleans.chunked(2): ${booleans.chunked(2)}")
    println("booleans.chunked(3, 1): ${booleans.chunked(3, 1)}")
    
    println("\n=== Complex transform functions ===")
    
    // Transform to different types
    val toStrings = numbers.chunked(3) { chunk ->
        chunk.joinToString("+")
    }
    println("to strings: $toStrings")
    
    val toMaps = numbers.chunked(4) { chunk ->
        chunk.mapIndexed { index, value -> index to value }.toMap()
    }
    println("to maps: $toMaps")
    
    val toBooleans = numbers.chunked(3) { chunk ->
        chunk.all { it > 5 }
    }
    println("to booleans: $toBooleans")
    
    // Transform with step
    val stepToSum = numbers.chunked(2, 3) { chunk ->
        chunk.sum()
    }
    println("step to sum: $stepToSum")
    
    println("\n=== Performance and behavior tests ===")
    
    // Large collection
    val large = (1..100).toList()
    val largeChunked = large.chunked(10, 5) { chunk.size }
    println("large chunked sizes: ${largeChunked.take(5)}")
    
    // Verify chunk contents
    val testList = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9)
    val expectedChunks = listOf(listOf(1, 2, 3), listOf(3, 4, 5), listOf(5, 6, 7), listOf(7, 8, 9))
    val actualChunks = testList.chunked(3, 2)
    println("expected: $expectedChunks")
    println("actual: $actualChunks")
    println("match: ${expectedChunks == actualChunks}")
    
    println("\n=== Special cases ===")
    
    // Step equal to collection size
    println("numbers.chunked(3, 10): ${numbers.chunked(3, 10)}")
    
    // Size = 1
    println("numbers.chunked(1, 2): ${numbers.chunked(1, 2)}")
    println("numbers.chunked(1, 1): ${numbers.chunked(1, 1)}")
    
    // Transform that returns empty collections
    val emptyTransform = numbers.chunked(3) { emptyList<Int>() }
    println("empty transform: $emptyTransform")
    
    // Transform with side effects (shouldn't affect chunking)
    var counter = 0
    val sideEffectTransform = numbers.chunked(2) { chunk ->
        counter++
        chunk.map { it + counter }
    }
    println("side effect: $sideEffectTransform")
    println("counter: $counter")
}
