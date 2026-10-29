import AppFolderKit
import SwiftUI
import UIKit

/// A local example using the widget's grid and overflow layout calculations.
/// Preview choices never write widget configuration or access the network.
struct WidgetPreviewView: View {
    private struct Example {
        let name: LocalizedStringKey
        let symbol: String
        let color: Color
    }

    private static let examples: [Example] = [
        .init(name: "相机", symbol: "camera.fill", color: .gray),
        .init(name: "地图", symbol: "map.fill", color: .green),
        .init(name: "日历", symbol: "calendar", color: .red),
        .init(name: "照片", symbol: "photo.on.rectangle.angled", color: .purple),
        .init(name: "时钟", symbol: "clock.fill", color: .indigo),
        .init(name: "天气", symbol: "cloud.sun.fill", color: .cyan),
        .init(name: "音乐", symbol: "music.note", color: .pink),
        .init(name: "备忘录", symbol: "note.text", color: .orange),
        .init(name: "提醒事项", symbol: "checklist", color: .blue),
        .init(name: "计算器", symbol: "plus.forwardslash.minus", color: .orange),
        .init(name: "文件", symbol: "folder.fill", color: .blue),
        .init(name: "设置", symbol: "gearshape.fill", color: .gray),
    ]

    @State private var grid: FolderGrid = .nine
    @State private var showsTitles = false
    @State private var isExpanded = false
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var capacity: Int { grid.capacity(for: .systemSmall) }
    private var instruction: LocalizedStringKey {
        isExpanded ? "点击「返回」，收起文件夹" : "点击「其他」，试试原地展开"
    }
    private var expansion: FolderExpansionLayout {
        FolderExpansionLayout(
            family: .systemSmall, grid: grid,
            appCount: Self.examples.count - capacity
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            preview.padding(.top, 8)

            VStack(spacing: 6) {
                Text(instruction)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("这是小号示例，不会打开 App 或修改桌面。可在「我的分组」中预览中号和大号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Picker("网格", selection: $grid) {
                    Text("九宫格").tag(FolderGrid.nine)
                    Text("四宫格").tag(FolderGrid.four)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("preview.grid")

                Toggle("显示图标名称", isOn: $showsTitles)
                    .font(.subheadline)
                    .accessibilityIdentifier("preview.titles")
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onChange(of: grid) { _, _ in
            isExpanded = false
            page = 0
        }
    }

    private var preview: some View {
        let side: CGFloat = 170
        let count = grid.cellCount(for: .systemSmall)
        let metrics = FolderGridMetrics(
            tileCount: count, columns: grid.columns(for: .systemSmall),
            in: CGSize(width: side, height: side), showsTitles: showsTitles, family: .systemSmall
        )

        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(metrics.iconSide), spacing: metrics.spacing), count: metrics.columns),
            spacing: metrics.spacing
        ) {
            ForEach(0..<count, id: \.self) { index in
                if isExpanded {
                    switch expansion.role(forCell: index, onPage: page) {
                    case .back:
                        navigationCell("返回", symbol: "arrow.turn.up.left", metrics: metrics) {
                            changePage { isExpanded = false; page = 0 }
                        }
                    case .next:
                        navigationCell("更多", symbol: "ellipsis", metrics: metrics) {
                            changePage { page = (page + 1) % expansion.pageCount }
                        }
                    case .app(let offset):
                        exampleCell(Self.examples[capacity + offset], metrics: metrics)
                    case .empty:
                        Color.clear.frame(width: metrics.iconSide, height: metrics.cellHeight)
                            .accessibilityHidden(true)
                    }
                } else if index < capacity {
                    exampleCell(Self.examples[index], metrics: metrics)
                } else {
                    Button {
                        changePage { isExpanded = true; page = 0 }
                    } label: {
                        VStack(spacing: metrics.titleSpacing) {
                            miniFolder(side: metrics.iconSide)
                            if showsTitles { title("其他", metrics: metrics) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("其他")
                    .accessibilityHint("展开示例文件夹")
                    .accessibilityIdentifier("preview.openFolder")
                }
            }
        }
        .padding(metrics.margin)
        .frame(width: side, height: side, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }

    private func exampleCell(_ example: Example, metrics: FolderGridMetrics) -> some View {
        VStack(spacing: metrics.titleSpacing) {
            artwork(example, side: metrics.iconSide)
            if showsTitles { title(example.name, metrics: metrics) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(example.name))
    }

    private func artwork(_ example: Example, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
            .fill(example.color.gradient)
            .overlay {
                Image(systemName: example.symbol)
                    .font(.system(size: side * 0.49, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: side, height: side)
    }

    private func miniFolder(side: CGFloat) -> some View {
        let density = MiniGridDensity(cellSide: side)
        return RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
            .fill(.quaternary)
            .overlay {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(density.miniSide), spacing: density.spacing), count: density.columns),
                    spacing: density.spacing
                ) {
                    ForEach(0..<(density.columns * density.columns), id: \.self) { index in
                        artwork(Self.examples[capacity + index % (Self.examples.count - capacity)], side: density.miniSide)
                    }
                }
                .frame(width: side * MiniGridDensity.fillShare)
            }
            .frame(width: side, height: side)
    }

    private func navigationCell(
        _ name: LocalizedStringKey, symbol: String,
        metrics: FolderGridMetrics, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: metrics.titleSpacing) {
                RoundedRectangle(cornerRadius: metrics.iconSide * 0.22, style: .continuous)
                    .fill(.tint.opacity(0.12))
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: metrics.iconSide * 0.42, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                    .frame(width: metrics.iconSide, height: metrics.iconSide)
                if showsTitles { title(name, metrics: metrics) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
    }

    private func title(_ name: LocalizedStringKey, metrics: FolderGridMetrics) -> some View {
        Text(name)
            .font(.system(size: metrics.titleFontSize))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: metrics.iconSide, height: metrics.labelHeight)
    }

    private func changePage(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18), change)
    }
}
