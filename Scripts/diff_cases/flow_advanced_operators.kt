import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val transformed = flow<Int> {
        emit(1)
        emit(2)
        emit(3)
        emit(4)
    }
        .transform { it * 10 }
        .takeWhile { it <= 30 }
        .dropWhile { it < 20 }
        .toList()
    println(transformed)

    val concat = flow<Int> {
        emit(1)
        emit(2)
    }.flatMapConcat { value ->
        flow<Int> {
            emit(value)
            emit(value * 10)
        }
    }.toList()
    println(concat)

    val mergedFlat = flow<Int> {
        emit(1)
        emit(2)
    }.flatMapMerge { value ->
        flow<Int> {
            emit(value + 100)
            emit(value + 200)
        }
    }.toList()
    println(mergedFlat)

    val latestFlat = flow<Int> {
        emit(1)
        emit(2)
    }.flatMapLatest { value ->
        flow<Int> {
            emit(value)
            emit(value * 100)
        }
    }.toList()
    println(latestFlat)

    val left = flow<Int> {
        emit(1)
        emit(2)
        emit(3)
    }
    val right = flow<Int> {
        emit(10)
        emit(20)
        emit(30)
    }

    println(left.zip(right) { a, b -> a + b }.toList())
    println(left.combine(right) { a, b -> a * b }.toList())
    println(merge(left, right).toList())

    val buffered = flow<Int> {
        emit(5)
        emit(6)
        emit(7)
    }
        .buffer(2)
        .conflate()
        .flowOn(Dispatchers.Default)
        .debounce(1)
        .sample(1)
        .delayEach(1)
        .toList()
    println(buffered)
}
