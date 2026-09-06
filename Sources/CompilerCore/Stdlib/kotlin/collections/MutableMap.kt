package kotlin.collections

// KSP-946: keep the MutableMap nominal declaration in bundled Kotlin source.
// Its mutation members and Map query views remain compiler/runtime-backed
// residuals until their dedicated API migration tasks are completed.
public interface MutableMap<K, V> : Map<K, V>
