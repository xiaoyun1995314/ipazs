import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Ways to support iPadn. Everything here is optional: the app stays free.
enum SupportLinks {
    static let releases = URL(string: "https://github.com/xiaoyun1995314/ipazs/releases")!
    static let repository = URL(string: "https://github.com/xiaoyun1995314/ipazs")!
}

struct SupportView: View {
    @EnvironmentObject private var store: ToolStore
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    private static let pink = Color(red: 0.98, green: 0.3, blue: 0.45)

    var body: some View {
        Form {
            Section { header }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))

            Section {
                Link(destination: SupportLinks.releases) { Label("GitHub 版本发布页", systemImage: "shippingbox") }
                Link(destination: SupportLinks.repository) { Label("在 GitHub 上点个 Star", systemImage: "star") }
            } header: { Text("项目链接") }
        }
        .toolPage().navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
        .task { if !reduceMotion { try? await Task.sleep(for: .milliseconds(350)); beat += 1 } }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                // A few small hearts around the big one, like confetti.
                ForEach(Self.confetti.indices, id: \.self) { index in
                    let item = Self.confetti[index]
                    Image(systemName: "heart.fill").font(.system(size: item.size))
                        .foregroundStyle(Self.pink.opacity(item.opacity))
                        .rotationEffect(.degrees(item.angle))
                        .offset(x: item.x, y: item.y)
                }
                Circle().fill(Self.pink.opacity(0.12)).frame(width: 104, height: 104)
                Image(systemName: "heart.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.58), Color(red: 0.94, green: 0.2, blue: 0.36)],
                                                    startPoint: .top, endPoint: .bottom))
                    .compatibleBounce(trigger: beat)
                    .onTapGesture { if !reduceMotion { beat += 1 } }
            }
            .frame(height: 130)
            .accessibilityHidden(true)
            Text("感谢你使用 ipazs").font(.title3.weight(.bold))
            Text("ipazs 免费开源、没有广告，欢迎在 GitHub 关注并点 Star 支持开发。")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private struct Confetti { let x: CGFloat; let y: CGFloat; let size: CGFloat; let angle: Double; let opacity: Double }
    private static let confetti = [
        Confetti(x: -88, y: -30, size: 16, angle: -18, opacity: 0.55),
        Confetti(x: -66, y: 34, size: 11, angle: 12, opacity: 0.35),
        Confetti(x: -112, y: 18, size: 8, angle: -6, opacity: 0.3),
        Confetti(x: 86, y: -36, size: 12, angle: 16, opacity: 0.4),
        Confetti(x: 102, y: 20, size: 17, angle: 22, opacity: 0.55),
        Confetti(x: 64, y: 44, size: 9, angle: -10, opacity: 0.3),
    ]
}
