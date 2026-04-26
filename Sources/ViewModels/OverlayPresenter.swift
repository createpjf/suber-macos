import SwiftUI

// ┌───────────── OverlayPresenter — popover-root 弹窗协调器 ───────────────────┐
// │                                                                            │
// │  v1.8.0 修复：v1.7.1 加的 `.popoverOverlay(isPresented:)` modifier 用      │
// │  ZStack 包裹被它修饰的视图。问题是当它挂在 AutopilotSettingsSection      │
// │  这种深嵌在 SettingsView 的 ScrollView { VStack { sections } } 里的子视图  │
// │  上时，ZStack 继承的边界是 section 的自然内容高度，不是整个 popover 高度。│
// │  `.frame(maxWidth/maxHeight: .infinity)` 只填满 section 那一块，弹窗就     │
// │  渲染成 inline "挂在 Autopilot 标题下面" 的样子，被截掉一半。            │
// │                                                                            │
// │  本 presenter 是 env-object：任何视图调 `present(SomeModalView())`，       │
// │  实际渲染发生在 `MenuBarView.body` 顶层 ZStack（popover 根节点）里         │
// │  通过 `if let content = presenter.content { content.frame(.infinity)... }`│
// │  那时 `.infinity` 才真的是 480×520 整个 popover。                          │
// │                                                                            │
// │  适用：                                                                    │
// │    - IMAPAccountSheet（深嵌在 Settings → Autopilot section）              │
// │    - AutopilotConsentSheet（同）                                          │
// │    - CancelConfirmationSheet（ListView / DayDetailView 触发）             │
// │                                                                            │
// │  不适用：                                                                  │
// │    - Add Subscription 表单 — 已挂在 MenuBarView 根，formOverlay 就地 OK   │
// │    - .alert / .confirmationDialog — 走 NSAlert at .modalPanel level，    │
// │      跟 popover 解耦，不需要这套                                          │
// │    - 多步 Import 流 — 走独立 Window scene + WindowActivationCoordinator   │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

@MainActor
final class OverlayPresenter: ObservableObject {
    @Published private(set) var content: AnyView?

    /// 把 view 包成 AnyView 暂存，等 MenuBarView 的根 ZStack 渲染。
    /// 调用方若已有 modal 在 present，需先 dismiss — 实践中由触发 UI 的
    /// disabled 状态保证（参考 showAddForm 的 pattern）。
    func present<V: View>(_ view: V) {
        content = AnyView(view)
    }

    /// 关闭当前 overlay。Idempotent。
    func dismiss() {
        content = nil
    }

    /// 给 MenuBarView 的 .animation 用作触发 key（也方便单测）。
    var isPresenting: Bool { content != nil }
}
