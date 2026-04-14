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

Suber 常驻 macOS 菜单栏,帮你盯住每一笔订阅 —— Netflix、iCloud、ChatGPT、那个你早忘了的健身 App —— 续费日和月度总支出永远一眼可见。通过 iCloud 在多台 Mac 间同步,支持 20 多种货币,所有数据只存在本地和你的 iCloud 里。

<p align="center">
  <img src="Screenshots/calendar.png" width="260" alt="日历">
  &nbsp;
  <img src="Screenshots/list.png" width="260" alt="列表">
  &nbsp;
  <img src="Screenshots/add.png" width="260" alt="添加订阅">
</p>

## 功能

- **菜单栏常驻** —— 不占 Dock,一次点击即达
- **日历视图** —— 按月显示账单日,点击日期查看当天的所有账单详情
- **列表视图** —— 支持按名称 / 分类 / 网址 / 备注搜索,按下次账单 / 名称 / 金额 / 添加时间排序,按状态筛选
- **Dashboard** —— 月度支出、六个月趋势图、分类占比、Top 订阅
- **Widget** —— 小尺寸(月度支出)和中尺寸(即将到期的订阅)桌面小组件
- **iCloud 同步** —— 通过 `NSUbiquitousKeyValueStore` 在多台 Mac 间同步订阅和设置
- **多币种** —— 20+ 货币,自动按汇率换算为你的主货币
- **图片自动识别** —— 把收据或邮件截图拖进添加表单,基于 Vision 的 OCR 自动提取名称和金额
- **Siri / App Intents** —— "添加一个 Netflix 订阅"、"我这个月花了多少"
- **通知提醒** —— 账单前 1 / 2 / 3 / 5 / 7 天本地提醒,可配置
- **JSON 导入导出** —— 本地备份与恢复,并可导入 Suber Chrome 扩展导出的数据
- **浅色 / 深色** —— 跟随系统外观
- **字体** —— 内置 Space Grotesk

## 安装

在 [最新 release](../../releases/latest) 下载 `Suber-1.4.0.dmg`(或更新的版本),双击挂载,把 **Suber.app** 拖进 **Applications**,然后从 Applications 启动。

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
