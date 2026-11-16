# Swevo 项目交接

Swevo 是以视频文件为核心的工具，提供播放、编辑和导出，运镜是教程和练习的使用场景。使用原生 SwiftUI，最低 iOS 17，工程与共享 Scheme 均为 `Swevo`。本文件记录 2026-11-13 的交付和用户确认的约定。后续状态以本项目的代码、配置和新验证记录为准。

## 业务与测试约定

- 业务沿用 Clipo。「视频」页的「课程链接或短码」通过 `search-check` 进入可纵向切换的全屏播放器。游客登录、推荐、收藏、离线播放、编辑导出、额度、开屏与激励广告、订阅和恢复购买继续走原有路径。订阅与媒体导出保留服务端权益校验。
- 当前是测试配置。API 为 `https://devapi.io-jp.com`，`getV2.name` 为 `Swevo`，取自 `SWEVO_RELEASE_NAME`。Bundle ID 为 `im.seex.lobo`，游客登录 `source` 和业务 `packageName` 同源。五包共用测试 BID，同一设备依次安装。
- 广告使用 Clipo 的 Google 官方演示 App ID 和开屏、激励广告位。官网、用户协议、隐私政策使用 HTTPS 占位链接。测试商品为月付 `coins_1.99` USD 9.99、年付 `conis_4.99` USD 99.99。会员页展示 StoreKit 返回的本地化价格和账期。
- 播放联调用 Clipo 的原测试短码，在「课程链接或短码」中手动输入。短码和广告配置见工具包的 [Clipo 基线](/Users/chengdupengyuyan/.codex/skills/toolkit/references/clipo-baseline.md) 第 1、5 节。Clipo 源工程位于 `/Users/chengdupengyuyan/Fun/Clipo`。
- 用户确认本项目测试通过后，再收集尚未提供的正式 BID、API 域名、广告 App ID 和广告位、官网、用户协议和隐私政策。切换时 Bundle ID、登录 `source` 与业务 `packageName` 一起使用正式 BID，`getV2.name` 继续用 `Swevo`。核对正式月年商品与后台订单映射。

## 本项目的原创界面

- 底栏为视频、工具、文件、我的。首页优先从「文件」或「照片」打开视频，并按打开时间显示最近的本地视频和离线下载。运镜计划、日志、教程和现场指南从「课程链接或短码」进入。
- 编辑页以深色预览和播放进度为主，提供裁剪、画幅、旋转、镜像、速度和音频处理。导出成品保存到「文件」的「导出」分类，也可以通过系统分享保存到「文件」App。
- 文件页含导入、离线视频、导出和收藏。列表优先展示文件名和视频画面，宽屏使用分类侧栏。实现见 `Swevo/Features/LibraryView.swift`。
- Plus 页展示实际观看、下载和导出权益，以及 StoreKit 返回的本地化价格和账期。恢复购买位于页上方，从「我的」及原有额度或导出入口打开。实现见 `Swevo/Features/MembershipView.swift`。
- 后续 UI 工作按全局 UI 技能约定使用 `ui-design-reference`、`ui-taste` 和适用的原创素材工作流。iOS 适配按 Duo 约定，保留当前 SwiftUI 和各主题的交互设计。

## 交付时的验证状态

- 源码核对覆盖文件导入、回看、导出、导航、会员文案及课程返回路径。播放和广告的日志入口见 `README.md`。
- 待运行验证的事项包括编译、模拟器和真机显示、Duo 布局、测试后台返回、短码播放、广告以及 Apple Sandbox 购买与恢复。按用户约定，默认只做静态核对，编译和测试在用户明确要求时执行。
