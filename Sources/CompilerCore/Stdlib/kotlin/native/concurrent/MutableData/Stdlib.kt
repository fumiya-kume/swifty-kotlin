/*
 * Copyright 2010-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license
 * that can be found in the LICENSE file.
 *
 * Derived from kotlin-native runtime/src/main/kotlin/kotlin/native/concurrent/MutableData.kt.
 */

package kotlin.native.concurrent

@Deprecated("Support for the legacy memory manager has been completely removed. Use any regular collection instead.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class MutableData constructor(capacity: Int = 16) {}
