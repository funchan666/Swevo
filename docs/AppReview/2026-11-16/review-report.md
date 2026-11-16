<!-- appstore-review-audit-report:v1 -->
# Swevo App Store 送审源码审计

审计日期 2026-11-16 · 审计技能版本 1.1.0

Swevo iOS，原生 SwiftUI，部署目标 iOS 17。共享 Swevo Scheme 的 Archive 使用 Release，仓库默认继承测试配置。工作区基于 `8e383cd8441c`，含审计前已有改动与本轮修订。

静态检查 Swevo 源码、配置、订阅目录和资源引用，重点追踪 4.3 与内购。只读对照 Clipo 的首页、文件编辑、练习记录与购买链路。未取得实际送审包、App Store Connect 数据或后台实现。按本轮要求未编译、测试、启动模拟器、运行真机或调用业务服务。

送审前优先补齐三处源码确认的缺口，包括跨设备 Plus 恢复、正式发布配置和游客账号删除。4.3 风险来自实际产品流程与内容的重合，当前能验证的差异点是本地视频的区间保存、循环回看和带入剪辑。已展开首页视频历史，调整订阅金额和续费说明，并分开显示恢复失败与到账后的权益刷新结果。

## 待解决的发现

### AR-001 · P1 · 新设备缺少订单账本时无法通过客户端恢复 Plus

已确认 · 内购恢复 · 置信度高

我的 → View Plus plans／View membership → Restore purchases → StoreKit 恢复队列 → CommerceStore.confirm → 原订单服务器验证。

用同一 Apple 账户在另一台设备安装 Swevo，后者没有原订单账本。当前恢复分支要求先匹配该账本。重装后的游客身份变化也可能触发原账号不一致。

客户端会在请求验证前退出，或只能请求验证原 Swevo 账号的订单。正在付费的用户可能无法在另一台设备恢复 Plus、解除额度和使用导出。

#### 源码证据

- Keychain 新写入使用 ThisDeviceOnly，订单账本无法随系统迁移到另一台设备。 `Swevo/Core/APIClient.swift:59`
- 在线功能通过服务端游客接口取得独立 userId，并持久化该设备的会话。 `Swevo/Core/APIClient.swift:157`
- 根据本地订单绑定、已见交易号或原始交易号查找订单。新设备没有匹配项时停止，Apple 交易保留待处理。 `Swevo/Core/CommerceStore.swift:393`
- 验证请求携带原订单号并绑定原订单账号。随后只接受当前账号的权益。全面恢复仍依赖后台支持。 `Swevo/Core/CommerceStore.swift:418`

#### 适用规则

- 可恢复的内购需要有效的恢复机制，自动续期订阅应可在用户的各设备使用。 [3.1.1 / 3.1.2(a)](https://developer.apple.com/app-store/review/guidelines/)
- 恢复可从 Apple 的可验证收据识别原始交易。恢复记录与安装本地订单的对应关系需要业务服务维护。 [Restoring purchased products](https://developer.apple.com/documentation/storekit/restoring-purchased-products)

#### 整改与验收

1. 后台提供已购订阅认领路径，验证 Apple 收据或签名交易，并按 Bundle ID、商品、环境和原始交易标识匹配订单及权益。
2. 定义已绑定订阅的账户恢复或迁移规则，防止误把权益授予其他游客。客户端对缺少本地订单的交易接入认领路径，确认权益入账后完成交易。
3. 保留现有订单重试、幂等校验和服务端权益门控。客户端已修正等待及错误状态。

- 在设备 A 购买后，使用同一 Apple Sandbox 账户在设备 B 全新安装，按恢复入口获得与 A 对应的 Plus 权益，再执行受保护导出。
- 验证重装、已过期订阅、切换 Apple 账户、重复恢复和断网重试。核对权益和订单不会重复或串账号。

由购买服务与 iOS 内购跟进。预计工作量 M–L，取决于原始交易索引和账号迁移能力。

- 未获得正式服务端的认领接口、原始交易映射或账号恢复协议。新设备缺账本的客户端失败分支可以由源码复核。

### AR-002 · P1 · 仓库的默认 Release 仍使用测试服务和政策占位链接

已确认 · 发布与提审 · 置信度高

共享 Swevo Scheme → Archive Release → Swevo.xcconfig → Bundle ID、游客包名、后端、广告和政策 URL。

使用仓库默认 Release 归档，且 CI 或归档用户未提供正式覆盖值。

审核可能到达共用测试服务和临时内容，正式商品或账号配置无法匹配。应用内隐私政策仍打开通用占位页。

#### 源码证据

- 标准 Archive 操作使用 Release。 `Swevo.xcodeproj/xcshareddata/xcschemes/Swevo.xcscheme:74`
- 应用 Target 的 Release 配置直接继承当前 Swevo.xcconfig。 `Swevo.xcodeproj/project.pbxproj:393`
- 仍为共用测试 Bundle ID 和开发 API host，业务包名由 Bundle ID 派生。 `Config/Swevo.xcconfig:3`
- 官网和隐私政策为占位链接。默认 Terms of Use 已改到 Apple 标准协议。 `Config/Swevo.xcconfig:10`
- 开启广告演示模式，配置 Google 官方演示 App ID。 `Config/Swevo.xcconfig:20`

#### 适用规则

- 提交最终版本，提供可用的 URL、后台和内购。 [2.1(a) / 2.1(b)](https://developer.apple.com/app-store/review/guidelines/)
- 应用和 App Store Connect 需要提供实际适用的隐私政策。 [5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/)

#### 整改与验收

1. 用已注册的 Swevo 正式 Bundle ID、签名和 API 替换发布配置，保持登录和业务包名对齐并保留 getV2 的 Swevo 名称。
2. 填入可访问的支持站和实际隐私政策，核对 App Store Connect 上的链接及 EULA。若有自定义 EULA，同步客户端链接。
3. 按正式发布策略配置正式广告位或关闭广告，核对广告隐私披露。用正式商品映射匹配 StoreKit 与购买服务。

- 检查实际送审归档的有效身份、Info.plist、签名、隐私清单和端点配置。
- 用待送审版本确认正常用户可打开受支持的视频链接、浏览政策和读取内购商品。

由发布、后台和产品运营跟进。预计工作量 S–M，依赖正式配置与网站。

- 未见生产配置、CI 覆盖、签名结果或 App Store Connect 中的实际版本。

### AR-003 · P1 · 自动创建游客账号后缺少发起删除的入口

已确认 · 账户与隐私 · 置信度高

启动联网 → APIClient.signIn → 游客 userId → 我的 → 设置。

用户已有 Swevo 游客账号，需要从应用发起账号和关联数据的删除。

用户无法主动完成 Apple 要求的账号删除流程，购买归属与 Apple 续费的处理也无法在删除过程中说明。

#### 源码证据

- 自动请求游客会话，服务返回独立 userId 并写入本地会话。 `Swevo/Core/APIClient.swift:139`
- 设置提供语言、政策、网站和广告隐私选项。未见账户删除操作。 `Swevo/Features/AccountAccessViews.swift:283`
- 检索删除账号同义词、成员 API 和设置入口，未发现能发起删除的原生操作或定向链接。 `Swevo、Config、README.md`

#### 适用规则

- Apple 的指引明确覆盖自动生成的游客账户及关联数据。 [5.1.1(v)](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)

#### 整改与验收

1. 提供后台删除接口或能完成删除的专用网页，从账户设置直接发起，允许用户确认并获知处理结果。
2. 说明删除与 Apple 订阅取消各自的效果，给出系统订阅管理途径，按实际政策处理关联数据和依法保留的信息。

- 用授权测试游客提交删除，确认后台处理结果、会话失效、关联数据处理和订阅提醒。

由账户服务、iOS 设置和隐私运营跟进。预计工作量 M，依赖服务端数据删除和购买归属约定。

- 后台若已有删除能力，仍需提供正式可达的入口与客户端接入方式。

### AR-004 · P1 · Clipo 同源流程的 4.3 重合程度待核对

待验证 · 产品同质化 · 置信度中

首页在线链接 → 竖向播放 → 收藏、文件与订阅，以及可从首页和工具进入的原生视频区间回看。

同一开发者同时提交多个视频工具，且核心用法、内容库和订阅权益高度重合。

审核员可能将其识别为同一产品的变体。Swevo 的独立文件回看价值需要在实际操作和提审材料中能看到。

#### 源码证据

- 交接注明 Swevo 沿用 Clipo 的链接、推荐、离线、额度和订阅服务协议。 `AGENTS.md:7`
- 本地只读对照确认 Clipo 也有链接输入和视频工具入口。 `../Clipo/Clipo/Features/HomeView.swift:3`
- Clipo 也有文件编辑。另核对其发球练习日志已有 CSV 导出。 `../Clipo/Clipo/Features/PracticeVideoWorkspace.swift:110`
- Swevo 可为本地视频保存命名区间并持久化，支持循环播放与应用到剪辑。对照的 Clipo 源码未见该流程。 `Swevo/Features/PracticeVideoWorkspace.swift:457`
- 首页展开真实视频历史，最近一条预览放大，能进入本地视频及已有保存区间的回看路径。 `Swevo/Features/HomeView.swift:146`

#### 适用规则

- 评估是否以多个 Bundle ID 发行同款应用，或提供实质上难以区分的体验。 [4.3(a) / 4.3(b)](https://developer.apple.com/app-store/review/guidelines/)
- 应能实际使用原生功能，并在审核说明准确描述新功能和操作路径。 [4.2 / 2.3.1(a)](https://developer.apple.com/app-store/review/guidelines/)

#### 整改与验收

1. 将导入、标记区间、循环回看、带入剪辑、导出作为商店截图和审核说明的实际操作主线，标明导出需要 Plus。
2. 用相同口径对比同一开发者名下近期或计划提审应用的工作流、付费权益和内容。若只剩题材或视觉差异，合并同类产品或先完成有独立用途的功能。

- 在待审归档里从本地授权样片完成区间回看流程，再以真实发布内容和同开发者其他提审版本复核区别。
- 检查截图、描述、演示样片和 App Review Notes 可让审核员复现相同流程。

由产品、发布和 App Store Connect 运营跟进。预计工作量 S–L，取决于同系列重合程度。

- 本轮仅对照 Clipo 本地源码。缺少同开发者完整应用清单、生产内容与实际送审包，Apple 的个案判断未知。

## 客户端已修正

### AR-005 · P2 · 已修正订阅周期披露和恢复完成时的反馈

已修正 · 内购呈现及状态 · 置信度高

我的 → Plus → StoreKit 商品与价格 → Subscribe 或 Restore purchases。

商品账期与目录月年配置不符、Apple 恢复回调与订单处理时序不同，或服务器确认后权益刷新失败。

过去可能把队列无待处理交易当成恢复结果，并把已验单后的权益读取失败显示成交易待确认。年付总价和续期信息需要跟随当前选择。

#### 源码证据

- 展示与购买前都核对 StoreKit 商品 ID 和一个月／一年的实际周期。 `Swevo/Core/CommerceStore.swift:464`
- 恢复等待队列处理及当前账号上最新的服务端权益，区分无法确认与没有有效权益。 `Swevo/Core/CommerceStore.swift:535`
- 已有未完成交易时提供重试确认动作，避免用户重复发起新订单。 `Swevo/Features/MembershipView.swift:105`
- 续费摘要使用选中商品的本地化完整金额和周期。我的页在等待游客连接时仍可进入 Plus。 `Swevo/Features/MembershipView.swift:305`

#### 适用规则

- 审核能够找到和使用内购，订阅前清楚看到所付金额对应的服务。 [2.1(b) / 3.1.2(c)](https://developer.apple.com/app-store/review/guidelines/)
- 显著呈现每次扣款的全额与期限，并提供恢复和政策链接。 [Clearly describing subscriptions](https://developer.apple.com/app-store/subscriptions/)

#### 整改与验收

1. 已在本轮调整客户端展示、重试和结果状态，后续接入 AR-001 的跨设备权益认领。

- 后续在真实 Sandbox 商品上分别走月付、年付、取消、等待批准、断网及恢复回调，并核对金额与权益变化。

由iOS 内购跟进。预计工作量 S，源码已改，仍需交易联调。

- 关闭范围是源码里的展示及反馈逻辑。App Store Connect 商品、真实交易与跨设备恢复尚未验证。

## 送审前补齐

### GAP-001 · P1 · 正式 IAP 商品、协议和提交关联是否齐全

核对正式 App ID 下两个月年自动续期商品的 ID、同权益订阅组、完整价格、在售地区、本地化说明、审核截图、Ready for Review 和有效的 Paid Apps Agreement。首次提审该商品类型时，把新版本、新订阅组和本次要审核的两项商品放入同一提交。若启用试用或优惠，补对应期限及后续实付说明。

由App Store Connect 运营与账户持有人跟进。

### GAP-002 · P1 · 待送审包的后端是否正确处理 Apple Sandbox 和正式权益

用待送审身份检查正常可购状态、续订、取消、过期、退款、回调重试和新设备恢复。记录已验证环境与权益读回结果。当前客户端会透传可选的沙盒标记与验证字段，须核对服务端依据可信 Apple 数据区分环境，实际共享密钥保留在服务端，购买开关对审核和普通用户采用相同规则。

由购买服务、QA 与发布跟进。

### GAP-003 · P1 · 审核员能否用真实样片复现独立核心功能与线上权益

提供可导入的自有短片或授权样片，以及可播放的生产链接。审核说明写明视频页用 Open video 导入，工具页用 Mark a range 设置起止并 Save range，随后 Loop range 或 Use for trim。我的页打开 View Plus plans，展示 Restore purchases 和完整价格。如果启用需登录的路径，提供有效审核访问方式。预置订阅演示账号应使用已过期订阅以便审核购买流程。

由产品、内容与 App Store Connect 运营跟进。

### GAP-004 · P1 · 外部视频的播放、缓存、导出以及正式隐私材料是否有依据

记录生产素材来源及授权范围，逐一核对可播放、可缓存和可导出的权利。准备实际隐私与支持链接、App Privacy 表和 SDK 隐私报告。截图优先展示真实核心操作，并标清哪些操作需要 Plus。

由内容、隐私与发布跟进。

### GAP-005 · P2 · 新首页与订阅页在待审设备上的实际表现

后续人工检查窄屏、大字号、RTL 及 Duo 过渡的输入保留和滚动。验证已有本地和旧链接历史、新的在线历史、失败后返回编辑、离线回看与过期媒体 URL 的重开行为。确认月年周期全额显示，购买及恢复反馈可见。

由iOS 和 QA跟进。

## App Review Notes 英文草稿

提交时附上可访问的授权样片、有效视频链接和适用的审核访问方式。

> Swevo is a video file workspace for replaying and editing short sections. On the Videos tab, tap Open video to choose an MP4 or MOV file. In Tools, select Mark a range and choose the imported video. Set the start and end points, then tap Save range. Tap Loop range to review the section or Use for trim to apply it in the editor. Saved ranges can be reopened from Video history. Plus enables video and audio export.

> For subscriptions, open the Me tab and tap View Plus plans. Select the monthly or yearly plan to see its full price and billing period. Restore purchases is at the top of the same screen.

## 检查范围

- **发布配置** · 已查源码。检查 Scheme、Release 配置引用、Info.plist 变量和商品目录。实际签名与归档的最终值待核对。
- **启动与应用完整性** · 已查源码。追踪本地文件入口和游客联网状态。打开文件与区间回看入口可以脱离在线内容使用，设备操作待验证。
- **账户** · 已查源码。追踪设备识别、自动游客开户、Keychain 元数据和设置分组，检索账号删除同义项与路由。
- **隐私** · 待补证据。检查应用内链接、隐私清单和游客及搜索请求。待核对正式隐私政策、App Store Connect 隐私标签和最终广告 SDK 隐私报告。
- **支付** · 已查源码。追踪商品定价、服务端订单、Apple 队列、收据、交易完成、权益刷新与导出门控。待验证线上配置与 Sandbox 交易。
- **内容安全与授权** · 待补证据。检查后台视频字段进入播放器、缓存和导出的调用链。媒体样本、内容范围与实际授权待提供。
- **Web 与远程行为** · 已查源码。追踪 getV2 的平台、语言、时区和用户等输入，以及广告、推荐与购买开关的客户端读者。服务端分组规则和审核时的实际响应待核对。
- **依赖与平台 API** · 已查源码。静态核对 SwiftUI、StoreKit 1、AVFoundation、Google Mobile Ads／UMP 引用及既有 Duo 布局。未建立包体或设备证据。
- **产品重合与独立功能** · 待补证据。对照 Clipo 源码的链接播放、文件工具和购买路径。已找到 Swevo 独有的区间回看流程，待核对同开发者其他实际提审版本和内容。
- **提交材料** · 待补证据。核对 Apple 规则与本地提审要点。App Store Connect 版本、商品、截图和实际审核访问方式待提供。
- **首页与本地化** · 已查源码。检查真实播放写入、旧链接兼容、预览、错误返回和宽屏布局的源码。线上历史从新版本播放开始记录，保留最近 100 条在线记录。

## Apple 官方来源

下列相关正文于 2026-11-16 核对。

- 2.1 完整性与内购可用性、2.3 元数据、3.1.1 恢复、3.1.2 订阅、4.2 最低功能、4.3 同质化、5.1 隐私及 5.2.3 音视频下载授权。 [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- 审核使用 Sandbox，核对付费协议生效、商品读取和审核条件。 [Configure In-App Purchases for review in the sandbox](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases)
- 首次提交自动续期订阅时，新版本、新订阅组与所提审商品的关联。 [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
- 同等权益的订阅组、付款前所见的全额实付、期限和恢复方式，以及条款与隐私链接。 [Auto-renewable Subscriptions](https://developer.apple.com/app-store/subscriptions/)
- StoreKit 1 收据刷新、恢复交易与原始交易标识的关系。 [Restoring purchased products](https://developer.apple.com/documentation/storekit/restoring-purchased-products)
- 审核说明、素材访问、试玩条件和自动续期订阅的审核账户。 [Provide information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)
- 自动创建的游客账号、删除入口、数据删除与订阅处理。 [Offering account deletion in your app](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)
- App Store Connect 的默认 Apple 标准许可协议与自定义协议。 [Provide a custom license agreement](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement)
- 核对客户端默认使用条款的目标页面。 [Apple Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
- 核对容器宽度、安全区与保留区域如何影响新首页布局。 [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
