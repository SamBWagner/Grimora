import GrimoraCore
import SwiftUI

struct CardListDashboardView: View {
    var stats: CardListDashboardStats
    var includesLands: Bool
    var palette: GrimoraPalette
    var onIncludesLandsChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()
                .overlay(palette.hairline.color)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    CardListDashboardColorSection(stats: stats, palette: palette)
                        .frame(width: 310, alignment: .leading)

                    dashboardDivider

                    CardListDashboardValueSection(stats: stats, palette: palette)
                        .frame(width: 180, alignment: .leading)

                    dashboardDivider

                    CardListDashboardTypeSection(stats: stats, includesLands: includesLands, palette: palette)
                        .frame(width: 350, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    CardListDashboardColorSection(stats: stats, palette: palette)
                    CardListDashboardValueSection(stats: stats, palette: palette)
                    CardListDashboardTypeSection(stats: stats, includesLands: includesLands, palette: palette)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-list-dashboard")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Stats")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)

            Spacer(minLength: 0)

            Toggle("Include Lands", isOn: includesLandsBinding)
                .toggleStyle(.switch)
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("card-list-dashboard-include-lands-toggle")
        }
    }

    private var dashboardDivider: some View {
        Divider()
            .overlay(palette.hairline.color)
            .frame(height: 150)
    }

    private var includesLandsBinding: Binding<Bool> {
        Binding {
            includesLands
        } set: { newValue in
            onIncludesLandsChange(newValue)
        }
    }
}
