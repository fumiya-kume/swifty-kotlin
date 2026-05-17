import Foundation

// MARK: - Seeded Random (STDLIB-516)

/// A deterministic PRNG using the xorshift64* algorithm.
/// Each `Random(seed)` call creates a new instance whose state evolves
/// independently so that two instances with the same seed produce identical
/// sequences.
final class SeededRandomBox {
    /// Internal PRNG state (xorshift64*).
    var state: UInt64

    init(seed: Int) {
        // Kotlin's Random(seed) internally mixes the seed.  We use the same
        // initial-state derivation so that behaviour is deterministic and
        // consistent across runs.  A seed of 0 would stall xorshift, so we
        // mix it first.
        var s = UInt64(bitPattern: Int64(seed))
        // Murmur-style finaliser to spread bits.
        s = s &+ 0x9E3779B97F4A7C15
        s = (s ^ (s >> 30)) &* 0xBF58476D1CE4E5B9
        s = (s ^ (s >> 27)) &* 0x94D049BB133111EB
        s = s ^ (s >> 31)
        if s == 0 { s = 1 }          // xorshift must never be 0
        self.state = s
    }

    /// Returns the next pseudo-random UInt64.
    func nextBits() -> UInt64 {
        var s = state
        s ^= s >> 12
        s ^= s << 25
        s ^= s >> 27
        state = s
        return s &* 0x2545F4914F6CDD1D
    }

    /// Returns a random Int in [0, bound).
    func nextInt(bound: Int) -> Int {
        precondition(bound > 0)
        let b = UInt64(bound)
        return Int(nextBits() % b)
    }

    /// Returns a random Int in [from, until).
    func nextIntRange(from: Int, until: Int) -> Int {
        precondition(until > from)
        let range = UInt64(bitPattern: Int64(until) &- Int64(from))
        return from &+ Int(Int64(bitPattern: nextBits() % range))
    }

    /// Returns a random Int (full range).
    func nextFullInt() -> Int {
        Int(bitPattern: UInt(truncatingIfNeeded: nextBits()))
    }

    /// Returns a random Double in [0.0, 1.0).
    func nextDouble() -> Double {
        // Use 53 bits of randomness (IEEE-754 double significand width).
        let bits = nextBits() >> 11
        return Double(bits) / Double(1 << 53)
    }

    /// Returns a random Float in [0.0, 1.0).
    func nextFloat() -> Float {
        let bits = nextBits() >> 40
        return Float(bits) / Float(1 << 24)
    }

    /// Returns a random Bool.
    func nextBoolean() -> Bool {
        (nextBits() & 1) != 0
    }

    func nextULongBits() -> UInt64 {
        nextBits()
    }

    func nextUInt32Bits() -> UInt64 {
        nextBits() & UInt64(UInt32.max)
    }
}

// MARK: - SecureRandom (STDLIB-101)

final class SecureRandomBox {
    private var seeded: SeededRandomBox?

    func setSeed(_ seed: Int) {
        seeded = SeededRandomBox(seed: seed)
    }

    private func nextBits() -> UInt64 {
        if let seeded {
            return seeded.nextBits()
        }
        var rng = SystemRandomNumberGenerator()
        return rng.next()
    }

    func nextByte() -> Int {
        Int(Int8(truncatingIfNeeded: nextBits()))
    }
}

/// Extract a SeededRandomBox from a raw receiver value.
/// Returns `nil` when the receiver is 0 (= Random.Default / companion object).
private func seededBox(from raw: Int) -> SeededRandomBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return Unmanaged<SeededRandomBox>.fromOpaque(ptr).takeUnretainedValue()
}

private func secureRandomBox(from raw: Int) -> SecureRandomBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return Unmanaged<SecureRandomBox>.fromOpaque(ptr).takeUnretainedValue()
}

private func ulongPayload(_ raw: Int) -> UInt64 {
    UInt64(UInt(bitPattern: raw))
}

private func runtimeRandomULongBits(receiver: Int) -> UInt64 {
    if let box = seededBox(from: receiver) {
        return box.nextULongBits()
    }
    var rng = SystemRandomNumberGenerator()
    return rng.next()
}

private func runtimeRandomULongBelow(_ upperBound: UInt64, receiver: Int) -> UInt64 {
    precondition(upperBound > 0)
    if let box = seededBox(from: receiver) {
        return box.nextULongBits() % upperBound
    }
    if upperBound == UInt64.max {
        var rng = SystemRandomNumberGenerator()
        return rng.next() % upperBound
    }
    return UInt64.random(in: 0 ..< upperBound)
}

private func runtimeRandomULongRange(receiver: Int, from: UInt64, until: UInt64) -> UInt64 {
    let width = until &- from
    return from &+ runtimeRandomULongBelow(width, receiver: receiver)
}

private func uint32Payload(_ raw: Int) -> UInt64 {
    UInt64(UInt(bitPattern: raw) & UInt(UInt32.max))
}

private func runtimeRandomUInt32Bits(receiver: Int) -> UInt64 {
    if let box = seededBox(from: receiver) {
        return box.nextUInt32Bits()
    }
    return UInt64(UInt32.random(in: UInt32.min ... UInt32.max))
}

private func runtimeRandomUIntBelow(_ upperBound: UInt64, receiver: Int) -> UInt64 {
    precondition(upperBound > 0 && upperBound <= (UInt64(UInt32.max) + 1))
    if upperBound == 1 {
        return 0
    }
    let space = UInt64(UInt32.max) + 1
    let rejectionLimit = space - (space % upperBound)
    var candidate = runtimeRandomUInt32Bits(receiver: receiver)
    while candidate >= rejectionLimit {
        candidate = runtimeRandomUInt32Bits(receiver: receiver)
    }
    return candidate % upperBound
}

private func runtimeRandomUIntRange(receiver: Int, from: UInt64, until: UInt64) -> UInt64 {
    from + runtimeRandomUIntBelow(until - from, receiver: receiver)
}

// MARK: - Constructor

private func runtimeCreateSeededRandom(seed: Int) -> Int {
    let box = SeededRandomBox(seed: seed)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_random_create_seeded")
public func kk_random_create_seeded(_ seed: Int) -> Int {
    runtimeCreateSeededRandom(seed: seed)
}

@_cdecl("kk_java_random_new")
public func kk_java_random_new() -> Int {
    runtimeCreateSeededRandom(seed: Int.random(in: Int.min ... Int.max))
}

@_cdecl("kk_java_random_new_seed")
public func kk_java_random_new_seed(_ seed: Int) -> Int {
    runtimeCreateSeededRandom(seed: seed)
}

// MARK: - SecureRandom Constructor / Factory

@_cdecl("kk_secure_random_get_instance")
public func kk_secure_random_get_instance() -> Int {
    let box = SecureRandomBox()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_secure_random_set_seed")
public func kk_secure_random_set_seed(_ receiver: Int, _ seed: Int) -> Int {
    guard let box = secureRandomBox(from: receiver) else {
        return receiver
    }
    box.setSeed(seed)
    return receiver
}

@_cdecl("kk_secure_random_generate_seed")
public func kk_secure_random_generate_seed(_ receiver: Int, _ size: Int) -> Int {
    guard let box = secureRandomBox(from: receiver), size > 0 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var bytes: [Int] = []
    bytes.reserveCapacity(size)
    for _ in 0 ..< size {
        bytes.append(box.nextByte())
    }
    return registerRuntimeObject(RuntimeListBox(elements: bytes))
}

@_cdecl("kk_secure_random_next_bytes")
public func kk_secure_random_next_bytes(_ receiver: Int, _ arrayRaw: Int) -> Int {
    guard let box = secureRandomBox(from: receiver),
          let list = runtimeListBox(from: arrayRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var filled: [Int] = []
    filled.reserveCapacity(list.elements.count)
    for _ in list.elements {
        filled.append(box.nextByte())
    }
    return registerRuntimeObject(RuntimeListBox(elements: filled))
}

// MARK: - Random (STDLIB-165, STDLIB-514, STDLIB-515, STDLIB-516, STDLIB-653, STDLIB-654, STDLIB-655)

@_cdecl("kk_random_default")
public func kk_random_default() -> Int {
    0
}

@_cdecl("kk_random_asKotlinRandom")
public func kk_random_asKotlinRandom(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_random_nextInt")
public func kk_random_nextInt(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return box.nextFullInt()
    }
    return Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextInt_until")
public func kk_random_nextInt_until(_ receiver: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextInt(bound: until)
    }
    return Int.random(in: 0 ..< until)
}

@_cdecl("kk_random_nextInt_range")
public func kk_random_nextInt_range(_ receiver: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > from else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextIntRange(from: from, until: until)
    }
    return Int.random(in: from ..< until)
}

@_cdecl("kk_random_nextLong")
public func kk_random_nextLong(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return box.nextFullInt()
    }
    return Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextLong_until")
public func kk_random_nextLong_until(_ receiver: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextInt(bound: until)
    }
    return Int.random(in: 0 ..< until)
}

@_cdecl("kk_random_nextLong_range")
public func kk_random_nextLong_range(_ receiver: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > from else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextIntRange(from: from, until: until)
    }
    return Int.random(in: from ..< until)
}

@_cdecl("kk_random_nextULong")
public func kk_random_nextULong(_ receiver: Int) -> Int {
    Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomULongBits(receiver: receiver)))
}

@_cdecl("kk_random_nextULong_until")
public func kk_random_nextULong_until(_ receiver: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let upper = ulongPayload(until)
    guard upper > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(upper)."
        )
        return 0
    }
    let value = runtimeRandomULongBelow(upper, receiver: receiver)
    return Int(bitPattern: UInt(truncatingIfNeeded: value))
}

@_cdecl("kk_random_nextULong_range")
public func kk_random_nextULong_range(_ receiver: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let lower = ulongPayload(from)
    let upper = ulongPayload(until)
    guard upper > lower else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random range is empty: \(lower)..\(upper)."
        )
        return 0
    }
    let value = runtimeRandomULongRange(receiver: receiver, from: lower, until: upper)
    return Int(bitPattern: UInt(truncatingIfNeeded: value))
}

@_cdecl("kk_random_nextULong_ulongRange")
public func kk_random_nextULong_ulongRange(_ receiver: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random range is empty."
        )
        return 0
    }
    let first = ulongPayload(range.first)
    let last = ulongPayload(range.last)
    guard last >= first else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random range is empty: \(first)..\(last)."
        )
        return 0
    }
    let width = last &- first &+ 1
    let value = width == 0
        ? runtimeRandomULongBits(receiver: receiver)
        : first &+ runtimeRandomULongBelow(width, receiver: receiver)
    return Int(bitPattern: UInt(truncatingIfNeeded: value))
}

@_cdecl("kk_random_nextUInt")
public func kk_random_nextUInt(_ receiver: Int) -> Int {
    Int(runtimeRandomUInt32Bits(receiver: receiver))
}

@_cdecl("kk_random_nextUInt_until")
public func kk_random_nextUInt_until(_ receiver: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let upper = uint32Payload(until)
    guard upper > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: 0..\(until).")
        return 0
    }
    return Int(runtimeRandomUIntBelow(upper, receiver: receiver))
}

@_cdecl("kk_random_nextUInt_range")
public func kk_random_nextUInt_range(_ receiver: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let lower = uint32Payload(from)
    let upper = uint32Payload(until)
    guard upper > lower else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return Int(lower)
    }
    return Int(runtimeRandomUIntRange(receiver: receiver, from: lower, until: upper))
}

@_cdecl("kk_random_nextUInt_uintRange")
public func kk_random_nextUInt_uintRange(_ receiver: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random.nextUInt expected a UIntRange.")
        return 0
    }
    let first = uint32Payload(range.first)
    let last = uint32Payload(range.last)
    guard range.step != 0, first <= last else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: Range is empty.")
        return Int(first)
    }
    let exclusiveUpper = last == UInt64(UInt32.max) ? UInt64(UInt32.max) + 1 : last + 1
    return Int(runtimeRandomUIntRange(receiver: receiver, from: first, until: exclusiveUpper))
}

@_cdecl("kk_random_nextFloat")
public func kk_random_nextFloat(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return kk_float_to_bits(box.nextFloat())
    }
    return kk_float_to_bits(Float.random(in: 0 ..< 1))
}

@_cdecl("kk_random_nextFloat_until")
public func kk_random_nextFloat_until(_ randomRaw: Int, _ untilBits: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let until = kk_bits_to_float(untilBits)
    guard until > 0, until.isFinite else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    if let box = seededBox(from: randomRaw) {
        return kk_float_to_bits(box.nextFloat() * until)
    }
    return kk_float_to_bits(Float.random(in: 0 ..< until))
}

@_cdecl("kk_random_nextFloat_range")
public func kk_random_nextFloat_range(_ randomRaw: Int, _ fromBits: Int, _ untilBits: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let from = kk_bits_to_float(fromBits)
    let until = kk_bits_to_float(untilBits)
    guard until > from, from.isFinite, until.isFinite else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    if let box = seededBox(from: randomRaw) {
        return kk_float_to_bits(from + (box.nextFloat() * (until - from)))
    }
    return kk_float_to_bits(Float.random(in: from ..< until))
}

@_cdecl("kk_random_nextDouble")
public func kk_random_nextDouble(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return kk_double_to_bits(box.nextDouble())
    }
    return kk_double_to_bits(Double.random(in: 0 ..< 1))
}

@_cdecl("kk_random_nextDouble_until")
public func kk_random_nextDouble_until(_ randomRaw: Int, _ untilBits: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let until = kk_bits_to_double(untilBits)
    guard until > 0.0, until.isFinite else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive and finite, but was \(until).")
        return 0
    }
    if let box = seededBox(from: randomRaw) {
        return kk_double_to_bits(box.nextDouble() * until)
    }
    return kk_double_to_bits(Double.random(in: 0.0 ..< until))
}

@_cdecl("kk_random_nextDouble_range")
public func kk_random_nextDouble_range(_ randomRaw: Int, _ fromBits: Int, _ untilBits: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let from = kk_bits_to_double(fromBits)
    let until = kk_bits_to_double(untilBits)
    guard until > from, from.isFinite, until.isFinite else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    if let box = seededBox(from: randomRaw) {
        return kk_double_to_bits(from + (box.nextDouble() * (until - from)))
    }
    return kk_double_to_bits(Double.random(in: from ..< until))
}

// MARK: - nextBytes (STDLIB-653)

private func runtimeRandomByte(receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return Int(Int8(truncatingIfNeeded: box.nextBits()))
    }
    return Int(Int8.random(in: Int8.min ... Int8.max))
}

private func runtimeRandomUByte(receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return Int(UInt8(truncatingIfNeeded: box.nextBits()))
    }
    return Int(UInt8.random(in: UInt8.min ... UInt8.max))
}

@_cdecl("kk_random_nextBytes")
public func kk_random_nextBytes(_ receiver: Int, _ arrayRaw: Int) -> Int {
    guard let list = runtimeListBox(from: arrayRaw) else {
        // If the argument is not a valid list, return an empty list.
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // Fill each element with a random byte in [-128, 127] (Kotlin's Byte range).
    var filled: [Int] = []
    filled.reserveCapacity(list.elements.count)
    for _ in list.elements {
        filled.append(runtimeRandomByte(receiver: receiver))
    }
    return registerRuntimeObject(RuntimeListBox(elements: filled))
}

@_cdecl("kk_random_nextBytes_size")
public func kk_random_nextBytes_size(_ receiver: Int, _ size: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard size >= 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random byte array size must be non-negative, but was \(size)."
        )
        return 0
    }
    let arrayRaw = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: size)))
    return kk_random_nextBytes(receiver, arrayRaw)
}

@_cdecl("kk_random_nextBytes_range")
public func kk_random_nextBytes_range(
    _ receiver: Int,
    _ arrayRaw: Int,
    _ fromIndex: Int,
    _ toIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if let list = runtimeListBox(from: arrayRaw) {
        var elements = list.elements
        guard fromIndex >= 0, toIndex >= fromIndex, toIndex <= elements.count else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: Random.nextBytes range [\(fromIndex), \(toIndex)) is out of bounds for size \(elements.count)."
            )
            return arrayRaw
        }
        for index in fromIndex..<toIndex {
            elements[index] = runtimeRandomByte(receiver: receiver)
        }
        list.elements = elements
        return arrayRaw
    }
    if let array = runtimeArrayBox(from: arrayRaw) {
        guard fromIndex >= 0, toIndex >= fromIndex, toIndex <= array.elements.count else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: Random.nextBytes range [\(fromIndex), \(toIndex)) is out of bounds for size \(array.elements.count)."
            )
            return arrayRaw
        }
        for index in fromIndex..<toIndex {
            array.elements[index] = runtimeRandomByte(receiver: receiver)
        }
        return arrayRaw
    }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "IllegalArgumentException: Random.nextBytes expected a ByteArray receiver."
    )
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

@_cdecl("kk_random_nextUBytes_size")
public func kk_random_nextUBytes_size(_ receiver: Int, _ size: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard size >= 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random.nextUBytes size (\(size)) must be non-negative."
        )
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    let array = RuntimeArrayBox(length: size)
    for index in 0..<size {
        array.elements[index] = runtimeRandomUByte(receiver: receiver)
    }
    return registerRuntimeObject(array)
}

@_cdecl("kk_random_nextUBytes")
public func kk_random_nextUBytes(_ receiver: Int, _ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    for index in array.elements.indices {
        array.elements[index] = runtimeRandomUByte(receiver: receiver)
    }
    return arrayRaw
}

@_cdecl("kk_random_nextUBytes_range")
public func kk_random_nextUBytes_range(
    _ receiver: Int,
    _ arrayRaw: Int,
    _ fromIndex: Int,
    _ toIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random.nextUBytes expected a UByteArray receiver."
        )
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    guard fromIndex >= 0, toIndex >= fromIndex, toIndex <= array.elements.count else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Random.nextUBytes range [\(fromIndex), \(toIndex)) is out of bounds for size \(array.elements.count)."
        )
        return arrayRaw
    }
    for index in fromIndex..<toIndex {
        array.elements[index] = runtimeRandomUByte(receiver: receiver)
    }
    return arrayRaw
}

@_cdecl("kk_random_nextBoolean")
public func kk_random_nextBoolean(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return kk_box_bool(box.nextBoolean() ? 1 : 0)
    }
    return kk_box_bool(Bool.random() ? 1 : 0)
}

// MARK: - nextBits (STDLIB-RANDOM-100)

@_cdecl("kk_random_nextBits")
public func kk_random_nextBits(_ receiver: Int, _ bitCount: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard bitCount >= 0, bitCount <= 32 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: bitCount (\(bitCount)) must be in 0..32."
        )
        return 0
    }
    if bitCount == 0 { return 0 }
    let raw: UInt64
    if let box = seededBox(from: receiver) {
        raw = box.nextBits()
    } else {
        var rng = SystemRandomNumberGenerator()
        raw = rng.next()
    }
    // Keep only the lower `bitCount` bits as an unsigned value, then
    // reinterpret as a signed Int so the result fits Kotlin's Int type.
    let mask: UInt64 = bitCount == 32 ? 0xFFFFFFFF : (1 << bitCount) - 1
    return Int(Int32(bitPattern: UInt32(raw & mask)))
}
