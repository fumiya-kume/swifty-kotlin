import Foundation
import RuntimeABI

extension CollectionLiteralLoweringPass {

    /// Rewrites java.io.File constructors and File member runtime calls.
    func rewriteFileCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // --- Rewrite File(path) → kk_file_new(path) (STDLIB-565)
        //     Rewrite File(parent, child) → kk_file_new_parent_child(parent, child) (STDLIB-IO-087) ---
        if callee == lookup.fileConstructorName {
            let fileCallee = arguments.count == 2
                ? lookup.kkFileNewParentChildName
                : lookup.kkFileNewName
            loweredBody.append(.call(
                symbol: nil,
                callee: fileCallee,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.fileExprIDs.insert(result.rawValue) }
            return true
        }

        // --- Rewrite File member calls: readText/writeText/readLines (STDLIB-320) ---
        if callee == lookup.readTextName,
           arguments.count == 1,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileReadTextName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return true
        }

        if callee == lookup.writeTextName,
           arguments.count == 2,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileWriteTextName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return true
        }

        if callee == lookup.appendTextName,
           arguments.count == 2,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileAppendTextName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return true
        }

        if callee == lookup.readLinesName,
           arguments.count == 1,
           state.fileExprIDs.contains(arguments[0].rawValue),
           isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkFileReadLinesName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            if let result { state.listExprIDs.insert(result.rawValue) }
            return true
        }

        // --- Rewrite File member calls (STDLIB-321) ---
        // Only rewrite calls on File expressions (tracked in state.fileExprIDs)
        if arguments.count >= 1, state.fileExprIDs.contains(arguments[0].rawValue) {
            let receiverID = arguments[0]
            let kkCallee: InternedString?

            switch callee {
            case lookup.readTextName:
                kkCallee = lookup.kkFileReadTextName
            case lookup.writeTextName:
                kkCallee = lookup.kkFileWriteTextName
            case lookup.appendTextName:
                kkCallee = lookup.kkFileAppendTextName
            case lookup.readLinesName:
                kkCallee = lookup.kkFileReadLinesName
            case lookup.existsName:
                kkCallee = lookup.kkFileExistsName
            case lookup.isFileName:
                kkCallee = lookup.kkFileIsFileName
            case lookup.isDirectoryName:
                kkCallee = lookup.kkFileIsDirectoryName
            case lookup.namePropertyName:
                kkCallee = lookup.kkFileNameName
            case lookup.nameWithoutExtensionName:
                kkCallee = lookup.kkFileNameWithoutExtensionName
            case lookup.pathPropertyName:
                kkCallee = lookup.kkFilePathName
            case lookup.forEachLineName:
                kkCallee = lookup.kkFileForEachLineName
            case lookup.useLinesName:
                kkCallee = lookup.kkFileUseLinesName
            case lookup.bufferedReaderName:
                // Only rewrite argument-less bufferedReader(); the runtime
                // function kk_file_bufferedReader does not accept charset/bufferSize.
                kkCallee = arguments.count == 1 ? lookup.kkFileBufferedReaderName : nil
            case lookup.bufferedWriterName:
                // Only rewrite argument-less bufferedWriter()
                kkCallee = arguments.count == 1 ? lookup.kkFileBufferedWriterName : nil
            case lookup.printWriterName:
                // Only rewrite argument-less printWriter() (STDLIB-IO-FN-027)
                kkCallee = arguments.count == 1 ? lookup.kkFilePrintWriterName : nil
            case lookup.walkName:
                kkCallee = lookup.kkFileWalkName
            case lookup.listFilesName:
                kkCallee = lookup.kkFileListFilesName
            case lookup.deleteName:
                kkCallee = lookup.kkFileDeleteName
            case lookup.mkdirsName:
                kkCallee = lookup.kkFileMkdirsName
            case lookup.readBytesName:
                kkCallee = lookup.kkFileReadBytesName
            case lookup.appendBytesName:
                kkCallee = lookup.kkFileAppendBytesName
            case lookup.appendTextName:
                kkCallee = lookup.kkFileAppendTextName
            // STDLIB-IO-087: Additional File operations
            case lookup.absolutePathName:
                kkCallee = lookup.kkFileAbsolutePathName
            case lookup.canonicalPathName:
                kkCallee = lookup.kkFileCanonicalPathName
            case lookup.parentName:
                kkCallee = lookup.kkFileParentName
            case lookup.lengthName:
                kkCallee = lookup.kkFileLengthName
            case lookup.lastModifiedName:
                kkCallee = lookup.kkFileLastModifiedName
            case lookup.createNewFileName:
                kkCallee = lookup.kkFileCreateNewFileName
            case lookup.canReadName:
                kkCallee = lookup.kkFileCanReadName
            case lookup.canWriteName:
                kkCallee = lookup.kkFileCanWriteName
            case lookup.canExecuteName:
                kkCallee = lookup.kkFileCanExecuteName
            default:
                kkCallee = nil
            }

            if let target = kkCallee {
                let memberArgs = (
                    callee == lookup.forEachLineName
                        || callee == lookup.useLinesName
                        || callee == lookup.writeTextName
                        || callee == lookup.appendTextName
                        || callee == lookup.appendBytesName
                ) ? [receiverID] + arguments.dropFirst() : [receiverID]
                loweredBody.append(.call(
                    symbol: nil,
                    callee: target,
                    arguments: memberArgs,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                // Track walk()/listFiles()/readLines() results as lists
                // so chained operations (forEach, sortedBy, etc.) are rewritten correctly
                if let result,
                   callee == lookup.walkName || callee == lookup.listFilesName || callee == lookup.readLinesName || callee == lookup.readBytesName
                {
                    state.listExprIDs.insert(result.rawValue)
                }
                // Track bufferedReader()/bufferedWriter()/printWriter() results as file-like exprs for chained member calls
                if let result,
                   callee == lookup.bufferedReaderName || callee == lookup.bufferedWriterName
                    || callee == lookup.printWriterName
                {
                    state.fileExprIDs.insert(result.rawValue)
                }
                return true
            }
        }

        // --- Append closureRaw argument for File lambda-accepting methods (STDLIB-322) ---
        // STDLIB-IO-FN-040: also covers `kk_buffered_reader_useLines`, the synthetic
        // stub for `kotlin.io.Reader.useLines` (resolved against `BufferedReader`).
        // STDLIB-IO-FN-017: also covers `kk_buffered_reader_forEachLine`, the synthetic
        // stub for `kotlin.io.Reader.forEachLine` (resolved against `BufferedReader`).
        // When the KIR callee is already rewritten via externalLinkName,
        // the lambda argument must be supplemented with closureRaw (0)
        // so the runtime receives (receiverRaw, fnPtr, closureRaw, outThrown).
        if callee == lookup.kkFileForEachLineName
            || callee == lookup.kkFileUseLinesName
            || callee == lookup.kkBufferedReaderUseLinesName
            || callee == lookup.kkBufferedReaderForEachLineName
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                symbol: symbol,
                callee: callee,
                arguments: arguments + [zeroExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            return true
        }

        return false
    }
}
