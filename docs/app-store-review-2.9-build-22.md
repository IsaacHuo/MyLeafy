# MyLeafy 2.9 build 22 审核提交清单

## App Store Connect

- 从当前被拒提交中移除 `com.isaachuo.leafy.ai.weekly.v2` 及其订阅组，但保留商品记录，不执行停售或删除。
- 在 App Description 末尾加入：

  `Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`

- 删除本版本元数据、宣传文本和审核截图中关于 Leafy AI 或周订阅可购买的描述。
- 隐私政策链接保持不变。
- 后续恢复订阅前，确认 Paid Apps Agreement 状态为 Active，并完成 Production/Sandbox JWS 验证。

## Review Notes

MyLeafy 2.9 (build 22) temporarily removes the public Leafy AI entry point and all in-app purchase access. The subscription product is not included in this submission.

We fixed both crashes identified from the symbolicated build 21 crash reports:

1. Timetable rendering now uses immutable snapshot values and no longer retains deleted SwiftData models.
2. Community notification badge refreshes now publish only on the MainActor and discard stale profile/subscription results.

We tested cold launch, idle operation, all four tabs (Timetable, Community, Campus, Profile), and repeated foreground/background transitions on iPad Air 11-inch (M3).

Terms of Use:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## 给审核团队的回复

Hello App Review Team,

Thank you for the detailed feedback. We have submitted MyLeafy 2.9 (build 22) with the following changes:

- Leafy AI and its in-app purchase flow have been removed from all public entry points, and the subscription is not included in this submission.
- We added the standard Apple Terms of Use link to the App Description.
- We fixed the two crashes found in the attached reports: an invalid SwiftData object retained by timetable rendering, and a community notification badge update published from a background executor.
- We tested cold launch, idle operation, all four tabs, and foreground/background transitions on iPad Air 11-inch (M3).

The attached screen recording demonstrates the tested flow. Thank you for reviewing the updated build.

## 录屏顺序

1. 展示安装的是 2.9 build 22。
2. 冷启动并在课表页空闲至少 30 秒。
3. 依次打开课表、社区、校园、我的四个 Tab。
4. 进入后台再回到前台，重复三轮。
5. 再次切换四个 Tab，证明 App 继续正常运行且没有 Leafy AI 或订阅入口。
