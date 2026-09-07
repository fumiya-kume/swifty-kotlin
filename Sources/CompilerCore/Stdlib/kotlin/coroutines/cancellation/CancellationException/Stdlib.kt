/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin.coroutines.cancellation

import kotlin.IllegalStateException
import kotlin.Throwable
import kotlin.internal.KsSymbolName

// KSP-1150: source owner for the complete CancellationException constructor surface.
// Dedicated runtime bridges preserve cancellation identity for catch and cancellation checks.

public open class CancellationException : IllegalStateException {
    @KsSymbolName("__kk_cancellation_exception_new")
    public constructor()

    @KsSymbolName("__kk_cancellation_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_cancellation_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_cancellation_exception_new_cause")
    public constructor(cause: Throwable?)
}
