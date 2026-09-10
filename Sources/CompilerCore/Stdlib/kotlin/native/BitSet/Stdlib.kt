package kotlin.native

private const val BIT_SET_ELEMENT_SIZE: Int = 64

private fun bitSetElementSize(bitSize: Int): Int =
    (bitSize + BIT_SET_ELEMENT_SIZE - 1) / BIT_SET_ELEMENT_SIZE

/** A vector of bits growing if necessary and allowing indexed bit operations. */
@ObsoleteNativeApi
public class BitSet(size: Int = BIT_SET_ELEMENT_SIZE) {
    // Store bits in 64-bit elements, matching Kotlin/Native's implementation.
    private var bits: LongArray = LongArray(bitSetElementSize(size))

    private val lastIndex: Int
        get() = size - 1

    public val lastTrueIndex: Int
        get() = previousSetBit(size)

    public val isEmpty: Boolean
        get() {
            var index = 0
            while (index < bits.size) {
                if (bits[index] != 0L) {
                    return false
                }
                index += 1
            }
            return true
        }

    public var size: Int = size
        private set

    /** Creates a bit set of the given length and evaluates [initializer] for every index. */
    public constructor(length: Int, initializer: (Int) -> Boolean) : this(length) {
        var index = 0
        while (index < length) {
            setInitialBit(index, initializer(index))
            index += 1
        }
    }

    private fun setInitialBit(index: Int, value: Boolean) {
        val elementIndex = index / BIT_SET_ELEMENT_SIZE
        val bitOffset = index % BIT_SET_ELEMENT_SIZE
        val mask = 1L shl bitOffset
        bits[elementIndex] = if (value) {
            bits[elementIndex] or mask
        } else {
            bits[elementIndex] and mask.inv()
        }
    }

    private fun bitToElementSize(bitSize: Int): Int =
        (bitSize + BIT_SET_ELEMENT_SIZE - 1) / BIT_SET_ELEMENT_SIZE

    private fun elementIndex(index: Int): Int = index / BIT_SET_ELEMENT_SIZE

    private fun bitOffset(index: Int): Int = index % BIT_SET_ELEMENT_SIZE

    private fun maskBetween(fromOffset: Int, toOffset: Int): Long {
        var result = 0L
        var offset = fromOffset
        while (offset <= toOffset) {
            result = result or (1L shl offset)
            offset += 1
        }
        return result
    }

    private fun setBitsWithMask(elementIndex: Int, mask: Long, value: Boolean) {
        val element = bits[elementIndex]
        bits[elementIndex] = if (value) {
            element or mask
        } else {
            element and mask.inv()
        }
    }

    private fun flipBitsWithMask(elementIndex: Int, mask: Long) {
        bits[elementIndex] = bits[elementIndex] xor mask
    }

    private fun clearUnusedTail() {
        if (bits.size == 0) {
            return
        }
        val lastElementIndex = elementIndex(lastIndex)
        val lastBitOffset = bitOffset(lastIndex)
        val lastArrayIndex = bits.size - 1
        bits[lastArrayIndex] = bits[lastArrayIndex] and maskBetween(0, lastBitOffset)
        var index = lastElementIndex + 1
        while (index < bits.size) {
            bits[index] = 0L
            index += 1
        }
    }

    private fun ensureCapacity(index: Int) {
        if (index < 0) {
            throw IndexOutOfBoundsException()
        }
        if (index >= size) {
            size = index + 1
            if (elementIndex(index) >= bits.size) {
                bits = bits.copyOf(bitToElementSize(index + 1))
            }
            clearUnusedTail()
        }
    }

    public fun set(index: Int, value: Boolean = true) {
        ensureCapacity(index)
        setBitsWithMask(elementIndex(index), 1L shl bitOffset(index), value)
    }

    public fun set(from: Int, to: Int, value: Boolean = true): Unit = set(from until to, value)

    public fun set(range: IntRange, value: Boolean = true) {
        if (range.start < 0 || range.endInclusive < 0) {
            throw IndexOutOfBoundsException()
        }
        if (range.start > range.endInclusive) {
            return
        }
        ensureCapacity(range.endInclusive)
        val fromElementIndex = elementIndex(range.start)
        val fromOffset = bitOffset(range.start)
        val toElementIndex = elementIndex(range.endInclusive)
        val toOffset = bitOffset(range.endInclusive)
        if (fromElementIndex == toElementIndex) {
            setBitsWithMask(fromElementIndex, maskBetween(fromOffset, toOffset), value)
            return
        }
        setBitsWithMask(fromElementIndex, maskBetween(fromOffset, BIT_SET_ELEMENT_SIZE - 1), value)
        var index = fromElementIndex + 1
        while (index < toElementIndex) {
            bits[index] = if (value) -1L else 0L
            index += 1
        }
        setBitsWithMask(toElementIndex, maskBetween(0, toOffset), value)
    }

    public fun clear(index: Int): Unit = set(index, false)

    public fun clear(from: Int, to: Int): Unit = set(from, to, false)

    public fun clear(range: IntRange): Unit = set(range, false)

    public fun clear() {
        var index = 0
        while (index < bits.size) {
            bits[index] = 0L
            index += 1
        }
    }

    public fun flip(index: Int) {
        ensureCapacity(index)
        flipBitsWithMask(elementIndex(index), 1L shl bitOffset(index))
    }

    public fun flip(from: Int, to: Int): Unit = flip(from until to)

    public fun flip(range: IntRange) {
        if (range.start < 0 || range.endInclusive < 0) {
            throw IndexOutOfBoundsException()
        }
        if (range.start > range.endInclusive) {
            return
        }
        ensureCapacity(range.endInclusive)
        val fromElementIndex = elementIndex(range.start)
        val fromOffset = bitOffset(range.start)
        val toElementIndex = elementIndex(range.endInclusive)
        val toOffset = bitOffset(range.endInclusive)
        if (fromElementIndex == toElementIndex) {
            flipBitsWithMask(fromElementIndex, maskBetween(fromOffset, toOffset))
            return
        }
        flipBitsWithMask(fromElementIndex, maskBetween(fromOffset, BIT_SET_ELEMENT_SIZE - 1))
        var index = fromElementIndex + 1
        while (index < toElementIndex) {
            bits[index] = bits[index].inv()
            index += 1
        }
        flipBitsWithMask(toElementIndex, maskBetween(0, toOffset))
    }

    private fun nextBit(startIndex: Int, lookFor: Boolean): Int {
        if (startIndex < 0) {
            throw IndexOutOfBoundsException()
        }
        if (startIndex >= size) {
            return if (lookFor) -1 else startIndex
        }
        var index = startIndex
        while (index < size) {
            if (get(index) == lookFor) {
                return index
            }
            index += 1
        }
        return if (lookFor) -1 else size
    }

    public fun nextSetBit(startIndex: Int = 0): Int = nextBit(startIndex, true)

    public fun nextClearBit(startIndex: Int = 0): Int = nextBit(startIndex, false)

    public fun previousBit(startIndex: Int, lookFor: Boolean): Int {
        var index = startIndex
        if (startIndex >= size) {
            if (!lookFor) {
                return startIndex
            }
            index = size - 1
        }
        if (index < -1) {
            throw IndexOutOfBoundsException()
        }
        while (index >= 0) {
            if (get(index) == lookFor) {
                return index
            }
            index -= 1
        }
        return -1
    }

    public fun previousSetBit(startIndex: Int): Int = previousBit(startIndex, true)

    public fun previousClearBit(startIndex: Int): Int = previousBit(startIndex, false)

    public operator fun get(index: Int): Boolean {
        if (index < 0) {
            throw IndexOutOfBoundsException()
        }
        if (index >= size) {
            return false
        }
        return bits[elementIndex(index)] and (1L shl bitOffset(index)) != 0L
    }

    public fun and(another: BitSet) {
        if (another.lastIndex >= 0) {
            ensureCapacity(another.lastIndex)
        }
        var index = 0
        while (index < another.bits.size) {
            bits[index] = bits[index] and another.bits[index]
            index += 1
        }
        while (index < bits.size) {
            bits[index] = 0L
            index += 1
        }
    }

    public fun or(another: BitSet) {
        if (another.lastIndex >= 0) {
            ensureCapacity(another.lastIndex)
        }
        var index = 0
        while (index < another.bits.size) {
            bits[index] = bits[index] or another.bits[index]
            index += 1
        }
    }

    public fun xor(another: BitSet) {
        if (another.lastIndex >= 0) {
            ensureCapacity(another.lastIndex)
        }
        var index = 0
        while (index < another.bits.size) {
            bits[index] = bits[index] xor another.bits[index]
            index += 1
        }
    }

    public fun andNot(another: BitSet) {
        if (another.lastIndex >= 0) {
            ensureCapacity(another.lastIndex)
        }
        var index = 0
        while (index < another.bits.size) {
            bits[index] = bits[index] and another.bits[index].inv()
            index += 1
        }
    }

    public fun intersects(another: BitSet): Boolean {
        var index = 0
        val limit = if (bits.size < another.bits.size) bits.size else another.bits.size
        while (index < limit) {
            if (bits[index] and another.bits[index] != 0L) {
                return true
            }
            index += 1
        }
        return false
    }

    override fun toString(): String {
        val builder = StringBuilder()
        var first = true
        var index = nextSetBit(0)
        builder.append('[')
        while (index != -1) {
            if (!first) {
                builder.append('|')
            }
            first = false
            builder.append(index)
            index = nextSetBit(index + 1)
        }
        builder.append(']')
        return builder.toString()
    }

    override fun hashCode(): Int {
        var value = 1234L
        var index = 0
        while (index < bits.size) {
            value = value xor (bits[index] * (index + 1))
            index += 1
        }
        return (value shr 32 xor value).toInt()
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) {
            return true
        }
        if (other !is BitSet) {
            return false
        }
        var index = 0
        val commonSize = if (bits.size < other.bits.size) bits.size else other.bits.size
        while (index < commonSize) {
            if (bits[index] != other.bits[index]) {
                return false
            }
            index += 1
        }
        val longestSize = if (bits.size > other.bits.size) bits.size else other.bits.size
        while (index < longestSize) {
            val value = if (index < bits.size) bits[index] else other.bits[index]
            if (value != 0L) {
                return false
            }
            index += 1
        }
        return true
    }

    public companion object {}
}
