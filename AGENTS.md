# Kstep 项目交接

Kstep 是以视频文件为核心的工具，提供播放、编辑和导出，运镜是教程和练习的使用场景。使用原生 SwiftUI，最低 iOS 17。工程为 `Swevo.xcodeproj`，应用 Target 为 `Kstep`，共享 Scheme 为 `kstep`。本文件记录 2026-11-13 的交付和用户确认的约定。后续状态以本项目的代码、配置和新验证记录为准。

## 业务与测试约定

- 业务沿用 Clipo。「视频」页的链接输入框通过 `search-check` 进入可纵向切换的全屏播放器。游客登录、推荐、收藏、离线播放、编辑导出、额度、开屏与激励广告、订阅和恢复购买继续走原有路径。订阅与媒体导出保留服务端权益校验。
- API 为 `https://o4r8xgd.kstep.site`，应用名与 `getV2.name` 共用 `SWEVO_RELEASE_NAME` 的 `Kstep`。打包使用测试 BID `im.seex.lobo`，游客登录 `source` 和业务 `packageName` 使用 `site.kstepchan.motion`。
- 广告 App ID 由 `Config/Swevo.xcconfig` 提供。开屏和激励广告位从 `getV2.adList` 读取，演示模式已关闭。官网、隐私政策和条款使用 `www.kstep.site`。测试商品为月付 `coins_1.99`、年付 `conis_4.99`，会员页展示 StoreKit 返回的本地化价格和账期。
- 播放联调使用当前 API 可访问的链接或短码。原测试配置和接口约定见工具包的 [Clipo 基线](/Users/chengdupengyuyan/.codex/skills/toolkit/references/clipo-baseline.md)。Clipo 源工程位于 `/Users/chengdupengyuyan/Fun/Clipo`。
- 切换到正式签名时，将 `PRODUCT_BUNDLE_IDENTIFIER` 设为已选定的 `site.kstepchan.motion`，并核对后台的广告位和商品映射。

## 本项目的原创界面

- 玻璃底栏用原创图标表示视频、工具、文件和我的。首页优先从「文件」或「照片」打开视频，支持直接粘贴链接。视频历史展开显示已打开的本地视频、已播放的离线下载和新记录的在线观看，旧链接记录也可重新打开。运镜计划、日志、教程和现场指南从「Browse and practice」进入。
- 编辑页以深色预览和播放进度为主，提供裁剪、画幅、旋转、镜像、速度和音频处理。可为本地视频保存带名称的片段，循环回看或带入裁剪。导出成品保存到「文件」的「导出」分类，也可以通过系统分享保存到「文件」App。
- 文件页含导入、离线视频、导出和收藏。列表优先展示文件名和视频画面，宽屏使用分类侧栏。实现见 `Swevo/Features/LibraryView.swift`。
- Plus 页展示实际观看、下载和导出权益，以及 StoreKit 返回的本地化价格和账期。恢复购买位于页上方，从「我的」及原有额度或导出入口打开。实现见 `Swevo/Features/MembershipView.swift`。
- 后续 UI 工作按全局 UI 技能约定使用 `ui-design-reference`、`ui-taste` 和适用的原创素材工作流。iOS 适配按 Duo 约定，保留当前 SwiftUI 和各主题的交互设计。

## 交付时的验证状态

- 源码核对覆盖文件导入、回看、导出、导航、会员文案及课程返回路径。播放和广告的日志入口见 `README.md`。
- 待运行验证的事项包括编译、模拟器和真机显示、Duo 布局、测试后台返回、短码播放、广告以及 Apple Sandbox 购买与恢复。按用户约定，默认只做静态核对，编译和测试在用户明确要求时执行。
- 4.3 和内购的送审缺口见 [Swevo 源码审计](docs/AppReview/2026-11-16/review-report.md)。
