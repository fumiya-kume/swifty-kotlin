class Flow<T>(private val values: MutableList<T>) {
    fun <R> map(transform: (T) -> R): Flow<R> {
        return Flow(values.map(transform).toMutableList())
    }

    fun filter(predicate: (T) -> Boolean): Flow<T> {
        return Flow(values.filter(predicate).toMutableList())
    }

    fun take(count: Int): Flow<T> {
        return Flow(values.take(count).toMutableList())
    }

    fun collect(consumer: (T) -> Unit) {
        for (value in values) {
            consumer(value)
        }
    }
}

class FlowBuilder<T> {
    private val values = mutableListOf<T>()

    fun emit(value: T) {
        values.add(value)
    }

    fun build(): Flow<T> = Flow(values)
}

fun <T> flow(block: FlowBuilder<T>.() -> Unit): Flow<T> {
    val builder = FlowBuilder<T>()
    builder.block()
    return builder.build()
}

fun main() {
    flow<Int> {
        emit(1)
        emit(2)
    }.map { it * 2 }
        .filter { it > 0 }
        .take(2)
        .collect { println(it) }
}
