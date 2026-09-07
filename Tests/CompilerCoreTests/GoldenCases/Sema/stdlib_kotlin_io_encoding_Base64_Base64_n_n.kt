package golden.sema

import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.text.Appendable

@OptIn(ExperimentalEncodingApi::class)
fun encodeRange(source: ByteArray): String = Base64.Default.encode(source, 1, 4)

@OptIn(ExperimentalEncodingApi::class)
fun encodeToByteArrayRange(source: ByteArray): ByteArray = Base64.Default.encodeToByteArray(source, 1, 4)

@OptIn(ExperimentalEncodingApi::class)
fun encodeIntoByteArrayRange(source: ByteArray, destination: ByteArray): Int =
    Base64.Default.encodeIntoByteArray(source, destination, 2, 1, 4)

@OptIn(ExperimentalEncodingApi::class)
fun encodeToAppendableRange(source: ByteArray, destination: Appendable): Appendable =
    Base64.Default.encodeToAppendable(source, destination, 1, 4)

@OptIn(ExperimentalEncodingApi::class)
fun decodeByteArrayRange(source: ByteArray): ByteArray = Base64.Default.decode(source, 1, 5)

@OptIn(ExperimentalEncodingApi::class)
fun decodeIntoByteArrayRange(source: ByteArray, destination: ByteArray): Int =
    Base64.Default.decodeIntoByteArray(source, destination, 2, 1, 5)

@OptIn(ExperimentalEncodingApi::class)
fun decodeCharSequenceRange(source: CharSequence): ByteArray = Base64.Default.decode(source, 1, 5)

@OptIn(ExperimentalEncodingApi::class)
fun decodeIntoCharSequenceRange(source: CharSequence, destination: ByteArray): Int =
    Base64.Default.decodeIntoByteArray(source, destination, 2, 1, 5)
