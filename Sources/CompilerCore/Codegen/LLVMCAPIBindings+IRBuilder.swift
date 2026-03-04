extension LLVMCAPIBindings {
    @discardableResult
    func buildRet(_ builder: LLVMBuilderRef?, value: LLVMValueRef?) -> LLVMValueRef? {
        buildRetFn(builder, value)
    }

    @discardableResult
    func buildRetVoid(_ builder: LLVMBuilderRef?) -> LLVMValueRef? {
        buildRetVoidFn(builder)
    }

    @discardableResult
    func buildBr(_ builder: LLVMBuilderRef?, destination: LLVMBasicBlockRef?) -> LLVMValueRef? {
        buildBrFn(builder, destination)
    }

    @discardableResult
    func buildCondBr(
        _ builder: LLVMBuilderRef?,
        condition: LLVMValueRef?,
        thenBlock: LLVMBasicBlockRef?,
        elseBlock: LLVMBasicBlockRef?
    ) -> LLVMValueRef? {
        buildCondBrFn(builder, condition, thenBlock, elseBlock)
    }

    func buildICmpEqual(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 32, lhs, rhs, $0) }
    }

    func buildICmpNotEqual(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 33, lhs, rhs, $0) }
    }

    func buildICmpSignedLessThan(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 40, lhs, rhs, $0) }
    }

    func buildICmpSignedLessOrEqual(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 41, lhs, rhs, $0) }
    }

    func buildICmpSignedGreaterThan(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 38, lhs, rhs, $0) }
    }

    func buildICmpSignedGreaterOrEqual(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 39, lhs, rhs, $0) }
    }

    func buildZExt(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let buildZExtFn else {
            return nil
        }
        return name.withCString { buildZExtFn(builder, value, type, $0) }
    }

    func buildAlloca(_ builder: LLVMBuilderRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let buildAllocaFn else {
            return nil
        }
        return name.withCString { buildAllocaFn(builder, type, $0) }
    }

    @discardableResult
    func buildStore(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, pointer: LLVMValueRef?) -> LLVMValueRef? {
        guard let buildStoreFn else {
            return nil
        }
        return buildStoreFn(builder, value, pointer)
    }

    func buildLoad(
        _ builder: LLVMBuilderRef?,
        type: LLVMTypeRef?,
        pointer: LLVMValueRef?,
        name: String
    ) -> LLVMValueRef? {
        if let buildLoad2Fn {
            return name.withCString { buildLoad2Fn(builder, type, pointer, $0) }
        }
        guard let buildLoadFn else {
            return nil
        }
        return name.withCString { buildLoadFn(builder, pointer, $0) }
    }

    func buildSelect(
        _ builder: LLVMBuilderRef?,
        condition: LLVMValueRef?,
        thenValue: LLVMValueRef?,
        elseValue: LLVMValueRef?,
        name: String
    ) -> LLVMValueRef? {
        guard let buildSelectFn else {
            return nil
        }
        return name.withCString { buildSelectFn(builder, condition, thenValue, elseValue, $0) }
    }

    func buildGlobalStringPtr(_ builder: LLVMBuilderRef?, value: String, name: String) -> LLVMValueRef? {
        guard let buildGlobalStringPtrFn else {
            return nil
        }
        return value.withCString { valueCString in
            name.withCString { nameCString in
                buildGlobalStringPtrFn(builder, valueCString, nameCString)
            }
        }
    }

    func buildPtrToInt(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let buildPtrToIntFn else {
            return nil
        }
        return name.withCString { buildPtrToIntFn(builder, value, type, $0) }
    }

    func buildIntToPtr(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let buildIntToPtrFn else {
            return nil
        }
        return name.withCString { buildIntToPtrFn(builder, value, type, $0) }
    }

    func buildAdd(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildAddFn(builder, lhs, rhs, $0) }
    }

    func buildSub(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildSubFn(builder, lhs, rhs, $0) }
    }

    func buildMul(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildMulFn(builder, lhs, rhs, $0) }
    }

    func buildSDiv(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildSDivFn(builder, lhs, rhs, $0) }
    }

    /// Bitwise/shift builder convenience methods (P5-103)
    func buildAnd(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        guard let buildAndFn else { return nil }
        return name.withCString { buildAndFn(builder, lhs, rhs, $0) }
    }

    func buildOr(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        guard let buildOrFn else { return nil }
        return name.withCString { buildOrFn(builder, lhs, rhs, $0) }
    }

    func buildXor(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        guard let buildXorFn else { return nil }
        return name.withCString { buildXorFn(builder, lhs, rhs, $0) }
    }

    func buildShl(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        guard let buildShlFn else { return nil }
        return name.withCString { buildShlFn(builder, lhs, rhs, $0) }
    }

    func buildAShr(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        guard let buildAShrFn else { return nil }
        return name.withCString { buildAShrFn(builder, lhs, rhs, $0) }
    }

    func buildLShr(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        guard let buildLShrFn else { return nil }
        return name.withCString { buildLShrFn(builder, lhs, rhs, $0) }
    }

    func buildNot(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, name: String) -> LLVMValueRef? {
        guard let buildNotFn else { return nil }
        return name.withCString { buildNotFn(builder, value, $0) }
    }

    func buildCall(
        _ builder: LLVMBuilderRef?,
        functionType: LLVMTypeRef?,
        callee: LLVMValueRef?,
        arguments: [LLVMValueRef?],
        name: String
    ) -> LLVMValueRef? {
        var mutable = arguments
        return name.withCString { cName in
            if let buildCall2Fn {
                return buildCall2Fn(builder, functionType, callee, &mutable, UInt32(mutable.count), cName)
            }
            guard let buildCallFn else {
                return nil
            }
            return buildCallFn(builder, callee, &mutable, UInt32(mutable.count), cName)
        }
    }

    func constInt(_ type: LLVMTypeRef?, value: UInt64, signExtend: Bool = false) -> LLVMValueRef? {
        constIntFn(type, value, signExtend ? 1 : 0)
    }

    func constPointerNull(_ type: LLVMTypeRef?) -> LLVMValueRef? {
        constPointerNullFn?(type)
    }
}
