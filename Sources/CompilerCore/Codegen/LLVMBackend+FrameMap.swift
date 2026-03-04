import Foundation

extension LLVMBackend {
    struct FrameMapPlan {
        let parameterSlotBySymbol: [SymbolID: Int]
        let exprSlotByID: [Int32: Int]
        let rootOffsets: [Int32]

        static let empty = FrameMapPlan(
            parameterSlotBySymbol: [:],
            exprSlotByID: [:],
            rootOffsets: []
        )

        var rootCount: Int {
            rootOffsets.count
        }
    }

    func frameMapDescriptorSymbol(for function: KIRFunction) -> String {
        "kk_frame_map_\(max(0, Int(function.symbol.rawValue)))"
    }

    func frameMapOffsetsSymbol(for function: KIRFunction) -> String {
        "kk_frame_map_offsets_\(max(0, Int(function.symbol.rawValue)))"
    }

    func buildFrameMapPlan(function: KIRFunction) -> FrameMapPlan {
        var parameterSlotBySymbol: [SymbolID: Int] = [:]
        var nextSlot = 0
        for parameter in function.params {
            parameterSlotBySymbol[parameter.symbol] = nextSlot
            nextSlot += 1
        }

        let exprIDs = collectFrameRootExprIDs(function: function)
        var exprSlotByID: [Int32: Int] = [:]
        for exprID in exprIDs {
            exprSlotByID[exprID.rawValue] = nextSlot
            nextSlot += 1
        }

        let pointerStride = max(1, MemoryLayout<Int>.size)
        let rootOffsets = (0 ..< nextSlot).map { slot in
            Int32(slot * pointerStride)
        }

        return FrameMapPlan(
            parameterSlotBySymbol: parameterSlotBySymbol,
            exprSlotByID: exprSlotByID,
            rootOffsets: rootOffsets
        )
    }

    func collectFrameRootExprIDs(function: KIRFunction) -> [KIRExprID] {
        var ids: Set<KIRExprID> = []

        for instruction in function.body {
            switch instruction {
            case let .jumpIfEqual(lhs, rhs, _):
                ids.insert(lhs)
                ids.insert(rhs)
            case let .constValue(result, _):
                ids.insert(result)
            case let .binary(_, lhs, rhs, result):
                ids.insert(lhs)
                ids.insert(rhs)
                ids.insert(result)
            case let .call(_, _, arguments, result, _, thrownResult, _):
                for arg in arguments {
                    ids.insert(arg)
                }
                if let result {
                    ids.insert(result)
                }
                if let thrownResult {
                    ids.insert(thrownResult)
                }
            case let .virtualCall(_, _, receiver, arguments, result, _, thrownResult, _):
                ids.insert(receiver)
                for arg in arguments {
                    ids.insert(arg)
                }
                if let result {
                    ids.insert(result)
                }
                if let thrownResult {
                    ids.insert(thrownResult)
                }
            case let .jumpIfNotNull(value, _):
                ids.insert(value)
            case let .copy(from, to):
                ids.insert(from)
                ids.insert(to)
            case let .rethrow(value):
                ids.insert(value)
            case let .returnIfEqual(lhs, rhs):
                ids.insert(lhs)
                ids.insert(rhs)
            case let .returnValue(value):
                ids.insert(value)
            default:
                continue
            }
        }

        return ids.sorted(by: { $0.rawValue < $1.rawValue })
    }
}
