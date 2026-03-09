import SwiftUI
@preconcurrency import Translation

struct TranslationPanelView: View {
    @ObservedObject var viewModel: TranslationViewModel

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: TranslationPanelLayout.sectionSpacing) {
                headerSection
                scrollContainer(panelHeight: proxy.size.height)
            }
            .padding(.horizontal, TranslationPanelLayout.horizontalPadding)
            .padding(.top, TranslationPanelLayout.topPadding)
            .padding(.bottom, TranslationPanelLayout.bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cardBackground)
            .overlay {
                cardBorder
            }
        }
        .translationTask(viewModel.configuration) { session in
            guard let stream = viewModel.translationJobStream() else {
                return
            }

            for await job in stream {
                DebugLog.write("translation.run start '\(job.candidate.normalizedText)'")

                do {
                    let response = try await session.translate(job.candidate.normalizedText)
                    viewModel.finish(response: response, for: job)
                } catch is CancellationError {
                    DebugLog.write("translation.run cancel '\(job.candidate.normalizedText)'")
                    return
                } catch {
                    viewModel.fail(error: error, for: job)
                }
            }
        }
    }

    private func scrollContainer(panelHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: shouldScroll(panelHeight: panelHeight)) {
            contentSection
        }
        .scrollDisabled(!shouldScroll(panelHeight: panelHeight))
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            headerIcon
            headerText
            Spacer(minLength: 12)
            targetBadge
        }
    }

    private var headerIcon: some View {
        Image(systemName: viewModel.errorMessage == nil ? "globe" : "exclamationmark.triangle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(headerIconStyle)
            .frame(width: 18, height: 18)
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("翻译")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.88))

            Text("Spotlight Result")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var targetBadge: some View {
        HStack(spacing: 7) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(compactTargetLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: TranslationPanelLayout.contentSpacing) {
            Text(primaryDisplayText)
                .font(primaryTextFont)
                .foregroundStyle(primaryTextColor)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: TranslationPanelLayout.dividerHeight)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text(viewModel.sourceText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cardBackground: some View {
        cardShape
            .fill(spotlightSurfaceColor)
            .overlay {
                cardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                .white.opacity(0.04),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                cardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                .black.opacity(0.01),
                                .clear,
                                .black.opacity(0.018),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
    }

    private var cardBorder: some View {
        cardShape
            .strokeBorder(.white.opacity(0.14), lineWidth: 0.7)
            .mask(
                VStack(spacing: 0) {
                    Color.clear.frame(height: 18)
                    Color.white
                }
            )
    }

    private var cardShape: some InsettableShape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: 14,
                bottomTrailing: 14,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    private var compactTargetLabel: String {
        viewModel.targetLabel.replacingOccurrences(of: "目标语言：", with: "")
    }

    private var spotlightSurfaceColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private var headerIconStyle: AnyShapeStyle {
        if viewModel.errorMessage != nil {
            return AnyShapeStyle(Color.red)
        }

        return AnyShapeStyle(.primary)
    }

    private var primaryDisplayText: String {
        viewModel.errorMessage ?? viewModel.resultText
    }

    private var primaryTextFont: Font {
        if viewModel.errorMessage != nil {
            return .system(size: TranslationPanelLayout.errorFontSize, weight: .medium)
        }

        return .system(size: TranslationPanelLayout.primaryFontSize, weight: .medium)
    }

    private var primaryTextColor: AnyShapeStyle {
        if viewModel.errorMessage != nil {
            return AnyShapeStyle(.red)
        }

        if viewModel.isLoading {
            return AnyShapeStyle(.secondary)
        }

        return AnyShapeStyle(.primary)
    }

    private func shouldScroll(panelHeight: CGFloat) -> Bool {
        panelHeight >= TranslationPanelLayout.maximumHeight - 1
    }
}
