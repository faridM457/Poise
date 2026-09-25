import SwiftUI

struct CustomScenarioCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("POISE PRO")
                        .font(PoiseType.eyebrow())
                        .tracking(PoiseType.eyebrowTracking)
                        .foregroundStyle(Color.poiseBlueDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.poiseSoftBlue)
                        .clipShape(Capsule())

                    Text("Create your own scenario")
                        .font(PoiseType.headline())
                        .foregroundStyle(Color.poiseNavy)

                    Text("Practice any professional conversation you choose.")
                        .font(PoiseType.subhead())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                PoiseIconBadge(icon: "ellipsis.message.fill", color: .poiseBlueDark, size: 54)
                    .accessibilityHidden(true)
            }

            Button("Create scenario", action: action)
                .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
                .accessibilityHint("Opens the custom scenario builder for Poise Pro members")
        }
        .padding(20)
        .poiseCard(fill: .poisePaleBlue, stroke: .poiseSoftBlue)
    }
}
