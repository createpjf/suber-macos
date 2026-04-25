<p align="right">
  <a href="./README.md">English</a> · <b>中文</b>
</p>

<p align="center">
  <img src="Screenshots/app-icon.png" width="128" alt="Suber App Icon">
</p>

<h1 align="center">Suber</h1>

<p align="center">
  原生 macOS 菜单栏订阅管理工具。<br>
  Swift + SwiftUI 构建。
</p>

<p align="center">
  <a href="https://github.com/createpjf/suber-macos/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/createpjf"><img src="https://img.shields.io/badge/GitHub-createpjf-181717?logo=github" alt="GitHub: createpjf"></a>
  <a href="https://twitter.com/createpjf"><img src="https://img.shields.io/badge/Twitter-@createpjf-1DA1F2?logo=twitter&logoColor=white" alt="Twitter: @createpjf"></a>
  <img src="https://img.shields.io/badge/platform-macOS_14+-black?logo=apple&logoColor=white" alt="Platform: macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
</p>

## 简介

Suber 常驻 macOS 菜单栏,帮你盯住每一笔订阅 —— Netflix、iCloud、ChatGPT、那个你早忘了的健身 App —— 续费日和月度总支出永远一眼可见。通过 iCloud 在多台 Mac 间同步,支持 20+ 货币,英文 + 简体中文双语,所有数据只存在本地和你的 iCloud 里。

**v1.6.0 — Autopilot** —— Suber 现在会在后台主动帮你盯着。Watch 从 Apple Mail 读取账单邮件,Sense 自动发现涨价、新订阅和重复扣款,Act 一键打开退订页面并在下个月验证扣款是否真的停了。详见下方 [Autopilot 部分](#autopilot-watch--sense--act)。

<p align="center">
  <img src="Screenshots/calendar.png" width="260" alt="日历">
  &nbsp;
  <img src="Screenshots/list.png" width="260" alt="列表">
  &nbsp;
  <img src="Screenshots/add.png" width="260" alt="添加订阅">
</p>

## 功能

### Autopilot(v1.6)—— Watch · Sense · Act

- **📬 邮件监听(Mail Watchdog)** —— 一次性授权后,Suber 在后台读取 Apple Mail 里的续费 / 发票 / 试用到期邮件。每天通过 `NSBackgroundActivityScheduler` 扫描一次。隐私保证:只保存金额和日期,邮件正文从不落盘。
- **🔔 变化哨兵(Change Sentinel)** —— 自动发现涨价、新订阅、重复扣款。菜单栏图标右上角红点显示未读数,每次扫描合并成一条系统通知。决策行直接告诉你涨幅 % 和年化影响,几秒就能决定下一步。
- **✂️ 一键退订(One-Tap Cancel)** —— 内置 40+ 服务的退订链接(Netflix、Spotify、ChatGPT、iCloud+、爱奇艺…)。Suber 在浏览器里打开退订页面,你完成取消,下个月 Suber 自动验证扣款是否停了 ——成功的话告诉你"Netflix 已取消,每年节省 $215";失败的话给你"Netflix 没取消,扣款仍在"的明确警告,而不是悄悄丢失。

### 日常基本功能

- **菜单栏常驻** —— 不占 Dock,一次点击即达
- **日历视图** —— 按月显示账单日,点击日期查看当天的所有账单详情,支持退订倒计时
- **列表视图** —— 支持按名称 / 分类 / 网址 / 备注搜索,按下次账单 / 名称 / 金额 / 添加时间排序,按状态筛选
- **Dashboard** —— 月度支出、六个月趋势图、分类占比、Top 订阅
- **Widget** —— 小尺寸(月度支出)和中尺寸(即将到期的订阅)桌面小组件
- **iCloud 同步** —— 订阅、设置和 v1.6 Autopilot 变化日志在多台 Mac 间同步
- **多币种** —— 20+ 货币,自动按汇率换算为你的主货币
- **图片自动识别** —— 把收据或邮件截图拖进添加表单,基于 Vision 的 OCR 自动提取名称和金额
- **银行 CSV 导入** —— 支付宝 / 微信支付 / 通用 CSV → 自动识别周期性扣款
- **双语** —— 英文 + 简体中文(根据 macOS 偏好语言自动选择)
- **Siri / App Intents** —— "添加一个 Netflix 订阅"、"我这个月花了多少"
- **通知提醒** —— 账单前 1 / 2 / 3 / 5 / 7 天本地提醒,可配置
- **JSON 导入导出** —— 本地备份与恢复,并可导入 Suber Chrome 扩展导出的数据
- **浅色 / 深色** —— 跟随系统外观
- **字体** —— 内置 Space Grotesk

## 安装

在 [最新 release](../../releases/latest) 下载最新的 `Suber-X.Y.Z.dmg`,双击挂载,把 **Suber.app** 拖进 **Applications**,然后从 Applications 启动。

发布版用 Developer ID 证书签名并经 Apple 公证 —— Gatekeeper 直接放行,不用右键打开也不用命令行去 quarantine。

> 需要 macOS 14(Sonoma)及以上。当前版本仅支持 Apple Silicon。

## 从源码构建

```bash
git clone https://github.com/createpjf/suber-macos.git
cd suber-macos

brew install xcodegen
xcodegen generate

xcodebuild build \
  -project Suber.xcodeproj -scheme Suber -configuration Release \
  -derivedDataPath .build
# 产物在 .build/Build/Products/Release/Suber.app
```

`scripts/build-dmg.sh` 封装了本地构建 + 打 DMG 的流程,仅适合本机测试。要做对外分发,还需要 Developer ID Application 证书和 Apple 公证流程(见 Apple 文档 *Notarizing macOS Software Before Distribution*)。

> **注意**:`xcodegen generate` 会从 `project.yml` 重新生成 `Suber.xcodeproj`,不会保留你在 Xcode 里选过的签名证书 / provisioning profile。重新生成之后需要再次打开 Xcode,在 **Signing & Capabilities** 里重新选团队。

## 项目结构

```
Sources/
├── SuberApp.swift                     # App 入口(MenuBarExtra + URL scheme)
├── Info.plist
├── Models/
│   ├── Constants.swift                # Theme / AppFont / 货币 / 分类
│   ├── KnownServices.swift            # 已识别服务元数据
│   ├── Settings.swift
│   └── Subscription.swift
├── Services/
│   ├── BillingCalculator.swift        # 下次账单日计算
│   ├── CloudSyncService.swift         # iCloud KVS 同步
│   ├── ExchangeRateService.swift      # 多币种汇率
│   ├── HotkeyService.swift            #(暂未启用)全局快捷键
│   ├── ImageCache.swift               # 内存 / 磁盘 / 网络三级 favicon 缓存
│   ├── ImageRecognitionService.swift  # Vision OCR(收据识别)
│   ├── NotificationService.swift      # 本地通知
│   ├── StorageService.swift           # JSON 持久化 + 导入导出
│   ├── SubscriptionTextParser.swift
│   ├── UpdateService.swift            # 检查 GitHub 新版本
│   └── URLSchemeHandler.swift         # suber:// 深链
├── Intents/
│   ├── AddSubscriptionIntent.swift    # Siri / Shortcuts
│   └── GetSpendIntent.swift
├── Utilities/
│   ├── CurrencyFormatter.swift
│   └── DateHelpers.swift
├── ViewModels/
│   ├── DashboardViewModel.swift
│   ├── SettingsStore.swift
│   └── SubscriptionStore.swift
└── Views/
    ├── MenuBarView.swift              # 根 tab 容器
    ├── TopBarView.swift
    ├── CalendarView.swift
    ├── CalendarDayCellView.swift
    ├── DayDetailView.swift
    ├── DashboardView.swift
    ├── ListView.swift
    ├── SubCardView.swift
    ├── SubscriptionFormView.swift
    ├── SettingsView.swift
    └── Components/
        ├── EmailParseView.swift
        ├── FilterBarView.swift
        ├── ImageDropZoneView.swift
        ├── LogoView.swift
        ├── SearchBarView.swift
        └── ToggleRow.swift

SuberWidget/
├── SuberWidget.swift                  # Widget bundle 入口
├── SmallSpendWidget.swift
├── MediumUpcomingWidget.swift
└── WidgetDataProvider.swift

Assets.xcassets/
├── AppIcon.appiconset/
└── MenuBarIcon.imageset/

Tests/
├── BillingCalculatorTests.swift
├── StorageServiceTests.swift
└── SubscriptionStoreTests.swift
```

## 技术栈

- **Swift 5.9 · SwiftUI · macOS 14+**
- **`MenuBarExtra`**(`.window` 风格)承载菜单栏弹窗界面
- **`WidgetKit`** 桌面小组件
- **`App Intents`** Siri 与快捷指令集成
- **`NSUbiquitousKeyValueStore`** iCloud 同步
- **`Vision` + `CoreImage`** 收据 / 截图 OCR
- **`UserDefaults` + `Codable`** JSON 持久化
- **`NSCache` + 磁盘缓存** 三级 favicon 缓存(内存 → 磁盘 → 网络)
- **URL scheme**(`suber://`)深链
- **`xcodegen`** 从 `project.yml` 生成 Xcode 项目
- **Space Grotesk** 自定义字体

## 作者

**createpjf** —— [@createpjf](https://twitter.com/createpjf)

Suber [Chrome 扩展](https://github.com/createpjf/suber) 的 macOS 端伴侣。

## 许可证

[MIT](LICENSE) © createpjf
