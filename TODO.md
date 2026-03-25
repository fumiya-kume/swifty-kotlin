# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-25

## 運用ルール

- `TODO.md` は未完了タスクを主に管理しつつ、直近で完了した大きめの項目は `[x]` で残してよい。
- タスクIDはカテゴリ接頭辞 (`LEX/TYPE/EXPR/CTRL/DECL/CLASS/PROP/FUNC/GEN/NULL/CORO/STDLIB/ANNO/TOOL/MPP`) + 3桁連番を使用する。
- 完了済みタスクを参照する場合は `[x]` または `既存実装済み` のどちらかで明示する。
- 共通完了条件（全タスク共通）:
  1. `Scripts/diff_kotlinc.sh` が exit 0 かつ stdout 完全一致
  2. golden テストが byte 一致
  3. エラーケースで `KSWIFTK-*` 診断コード出力
  4. 各項目末尾エッジケース golden が通過

---

## 未完了バックログ

監査で見つかった「簡易実装（Stub）」や「中途半端なパス」を将来の改善項目として追跡する。

- [ ] REFL-004: 実行時 `KClass` から読めるバイナリメタデータ（`MetadataSerializer` 等の活用）
  - 現状: 基本的なリフレクションAPIは実装済み（`RuntimeReflection.swift`）

---

### Kotlin Stdlib 互換性（独立タスク）

