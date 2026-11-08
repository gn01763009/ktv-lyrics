import AppKit
import KTVCore
import SwiftUI

/// The settings form. Every control changes the overlay as soon as it is touched.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private var displays: [DisplayChoice] { SettingsChoices.connectedDisplays() }

    var body: some View {
        Form {
            placementSection
            appearanceSection
            colorSection
            cardSection
            sourceSection
            systemSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 480, minHeight: 600)
    }

    // MARK: - Sections

    private var placementSection: some View {
        Section("位置") {
            Picker("顯示器", selection: displayBinding) {
                Text(SettingsChoices.autoDisplayName).tag(String?.none)
                ForEach(displays) { Text($0.name).tag(Optional($0.id)) }
                if let missing = missingDisplayID {
                    Text(SettingsChoices.missingDisplayName).tag(Optional(missing))
                }
            }
            slider("水平位置", anchorBinding(\.x), range: SettingBounds.anchor, format: "%.2f")
            slider("垂直位置", anchorBinding(\.y), range: SettingBounds.anchor, format: "%.2f")
            Text("也可以按 ⌃⌥K 進入移動模式，直接拖曳字幕。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var appearanceSection: some View {
        Section("外觀") {
            Picker("樣式", selection: presetBinding) {
                ForEach(StylePreset.allCases, id: \.self) { Text(SettingsChoices.presetName($0)).tag($0) }
            }
            slider("字幕大小", binding(\.size), range: SettingBounds.size, format: "%.0f")
            slider("不透明度", binding(\.opacity), range: SettingBounds.opacity, format: "%.2f")
            Picker("字體", selection: fontBinding) {
                ForEach(SettingsChoices.fonts(including: model.settings.style.fontName), id: \.self) { Text($0).tag($0) }
            }
            slider("描邊粗細", strokeBinding, range: SettingBounds.strokeWidth, format: "%.0f")
        }
    }

    private var colorSection: some View {
        Section("顏色") {
            colorRow("未唱文字", \.unsungFill) { $0.replacing(unsungFill: $1) }
            colorRow("已唱文字", \.sungFill) { $0.replacing(sungFill: $1) }
            colorRow("未唱描邊", \.unsungStroke) { $0.replacing(unsungStroke: $1) }
            colorRow("已唱描邊", \.sungStroke) { $0.replacing(sungStroke: $1) }
        }
    }

    private var cardSection: some View {
        Section("字卡") {
            Toggle("片頭字卡", isOn: binding(\.showTitleCard))
            Toggle("星星倒數", isOn: binding(\.showCountdown))
            Toggle("掌聲字卡", isOn: binding(\.showBanner))
        }
    }

    private var sourceSection: some View {
        Section("歌詞來源") {
            Toggle("使用網易雲音樂", isOn: binding(\.useNetEase))
            Text("非官方來源、可能隨時失效").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var systemSection: some View {
        Section("系統") {
            Toggle("開機自動啟動", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if let reason = model.loginItemError {
                Text(reason).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Rows

    private func slider(_ title: String, _ value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: format, value.wrappedValue)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func colorRow(
        _ title: String,
        _ path: KeyPath<OverlayStyle, RGBAColor>,
        _ replace: @escaping (OverlayStyle, RGBAColor) -> OverlayStyle
    ) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: model.settings.style[keyPath: path].nsColor) },
            set: { color in
                let next = RGBAColor(NSColor(color))
                model.update { $0.with(\.style, replace($0.style, next)) }
            }
        ))
    }

    // MARK: - Bindings

    private func binding<V>(_ path: WritableKeyPath<OverlaySettings, V>) -> Binding<V> {
        Binding(
            get: { model.settings[keyPath: path] },
            set: { value in model.update { $0.with(path, value) } }
        )
    }

    private func anchorBinding(_ axis: KeyPath<NormalizedPoint, Double>) -> Binding<Double> {
        Binding(
            get: { model.settings.anchor[keyPath: axis] },
            set: { value in
                model.update { settings in
                    let old = settings.anchor
                    let isX = axis == \NormalizedPoint.x
                    return settings.with(\.anchor, NormalizedPoint(x: isX ? value : old.x, y: isX ? old.y : value))
                }
            }
        )
    }

    private var presetBinding: Binding<StylePreset> {
        Binding(get: { model.settings.preset }, set: { model.selectPreset($0) })
    }

    private var displayBinding: Binding<String?> { binding(\.displayID) }

    private var fontBinding: Binding<String> {
        Binding(
            get: { model.settings.style.fontName },
            set: { name in model.update { $0.with(\.style, $0.style.replacing(fontName: name)) } }
        )
    }

    private var strokeBinding: Binding<Double> {
        Binding(
            get: { model.settings.style.strokeWidth },
            set: { width in model.update { $0.with(\.style, $0.style.replacing(strokeWidth: width)) } }
        )
    }

    private var missingDisplayID: String? {
        guard let id = model.settings.displayID, !displays.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}
