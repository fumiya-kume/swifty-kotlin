#!/bin/bash
git add -A
git commit -m "Fix CI regressions in PR #708

This commit fixes several issues that caused CI failures:

1. Fixed compilation errors in BuildASTPhase+ExpressionParserControlFlow.swift:
   - Changed binaryOp to binary (correct Expr enum case)
   - Changed andand to logicalAnd (correct BinaryOp enum case)
   - Added guard condition handling for when expressions

2. Fixed StringBuilder toString output issue:
   - Added StringBuilder case to kk_println_any function so StringBuilder objects print their string value instead of object reference

3. Fixed unused variable warnings:
   - Removed unused nonNullReceiverType in CallTypeChecker+MemberCallInference.swift
   - Replaced captureArg with _ in LambdaLowerer.swift
   - Removed unused subjectSymbol in ControlFlowLowerer+WhenExpr.swift

4. Fixed ControlFlowLowerer+WhenExpr.swift:
   - Updated to use identifierSymbols instead of currentPackageFQName for when subject variables

These changes should resolve the kotlinc Diff Regression test failures."
git push origin feat/stdlib-538-collection-to-extensions
