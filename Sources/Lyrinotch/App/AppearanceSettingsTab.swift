import SwiftUI
import LyrinotchCore

@MainActor
struct AppearanceSettingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section(L10n.t("section.appearance_preview")) {
                OverlayAppearancePreview(
                    appearance: model.appearance,
                    usesArtworkColor: model.preferences.lyricColorFromArtwork
                )
            }

            Section(L10n.t("section.lyric_appearance")) {
                SettingsSliderRow(
                    L10n.t("layout.font_size", Int(model.appearance.fontSize)),
                    value: fontSizeBinding,
                    in: 12...24,
                    step: 1
                )
                SettingsHelpText(L10n.t("layout.font_size_help"), tone: .tertiary)

                Toggle(
                    L10n.t("toggle.lyric_art_color"),
                    isOn: lyricColorFromArtworkBinding
                )
            }

            Section(L10n.t("section.liquid_glass_targets")) {
                Toggle(L10n.t("toggle.glass_notch"), isOn: liquidGlassOnNotchBinding)
                Toggle(L10n.t("toggle.glass_floating"), isOn: liquidGlassOnFloatingBinding)

                if model.appearance.usesLiquidGlassAnywhere {
                    Picker(L10n.t("picker.style"), selection: glassVariantBinding) {
                        Text(L10n.t("glass.clear")).tag(LiquidGlassVariant.clear)
                        Text(L10n.t("glass.tinted")).tag(LiquidGlassVariant.tinted)
                    }
                    .pickerStyle(.segmented)
                }

                SettingsSliderRow(
                    opacityLabel,
                    value: opacityBinding,
                    in: 0.25...0.95
                )

                SettingsHelpText(L10n.t("help.glass_targets"), tone: .tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var opacityLabel: String {
        let percentage = Int(model.appearance.opacity * 100)
        return model.appearance.usesLiquidGlassAnywhere
            ? L10n.t("opacity.glass", percentage)
            : L10n.t("opacity.classic", percentage)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { model.appearance.fontSize },
            set: { model.setFontSize($0) }
        )
    }

    private var lyricColorFromArtworkBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.lyricColorFromArtwork },
            set: { model.setLyricColorFromArtwork($0) }
        )
    }

    private var liquidGlassOnNotchBinding: Binding<Bool> {
        Binding(
            get: { model.appearance.liquidGlassOnNotch },
            set: { model.setLiquidGlassOnNotch($0) }
        )
    }

    private var liquidGlassOnFloatingBinding: Binding<Bool> {
        Binding(
            get: { model.appearance.liquidGlassOnFloating },
            set: { model.setLiquidGlassOnFloating($0) }
        )
    }

    private var glassVariantBinding: Binding<LiquidGlassVariant> {
        Binding(
            get: { model.appearance.glassVariant },
            set: { model.setGlassVariant($0) }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { model.appearance.opacity },
            set: { model.setOpacity($0) }
        )
    }
}

private struct OverlayAppearancePreview: View {
    let appearance: OverlayAppearance
    let usesArtworkColor: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.85), .blue.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t("preview.track_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(L10n.t("preview.current_lyric"))
                    .font(.system(size: appearance.fontSize, weight: .semibold))
                    .foregroundStyle(usesArtworkColor ? Color.cyan : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(L10n.t("preview.next_lyric"))
                    .font(.system(size: max(12, appearance.fontSize - 3)))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            ZStack {
                if appearance.usesLiquidGlassAnywhere {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(glassTintOpacity))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.45 + appearance.opacity * 0.55))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("accessibility.appearance_preview"))
    }

    private var glassTintOpacity: Double {
        switch appearance.glassVariant {
        case .clear:
            return appearance.opacity * 0.18
        case .tinted:
            return appearance.opacity * 0.5
        }
    }
}
