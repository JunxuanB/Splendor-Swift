# Luminore / 闪耀矿工

一款使用 SwiftUI 制作的竖屏宝石桌游，支持中英文、本地账号与 LAN
实时对战。基础版包含完整规则和 90 张发展卡；2–4 人采用官方资源规模，
5–7 人使用项目内明确标注的扩展桌规则。

## 工程

- 正式 App：`ios/Luminore.xcodeproj`
- 规则与协议：`ios/LuminoreCore`
- UI 视觉原型：`ios-ui-demo`（保留，不参与正式 App 构建）
- LAN 协议：`docs/03-lan-protocol-v1.md`

最低系统版本为 iOS 17，仅支持 iPhone 竖屏。使用 Xcode 26.6 打开正式
工程；验证目标为 iPhone 17 Pro 模拟器。

claude --dangerously-skip-permissions