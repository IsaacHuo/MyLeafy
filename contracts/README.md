# MyLeafy 跨平台契约

Android 与 iOS 不共享客户端源码，但必须共享以下契约：

- **Supabase Schema / API Contract / DTO 语义** → 见 `docs/engineering/supabase.md`、`supabase/schema-ledger.md`
- **教务 HTML Fixture 与 Parser Expected Result** → `jwxt/`
- **产品行为 / Error semantics** → `docs/engineering/android-migration.md`（含教务协议记录）

## `jwxt/`

强智教务（北京林业大学）页面样本与解析期望结果。

- `fixtures/`：从 iOS 回归测试（`leafyTests/`）提取的 HTML/JSON 样本，作为 jsoup 解析回归基线。iOS 测试与 Android 测试共用同一份样本，防止两端解析漂移。
- `expected/`：每个 fixture 的期望解析结果（JSON）。

新增解析器测试时，先向 `fixtures/` 添加样本，再写期望结果，最后让两端解析器都跑通同一组数据。
