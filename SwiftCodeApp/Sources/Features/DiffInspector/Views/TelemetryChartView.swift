import Charts
import SwiftUI

/// Native Swift Charts token telemetry breakdown view.
struct TelemetryChartView: View {
    let points: [TokenMetricPoint]
    let totalCostUSD: Double

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.stackMedium) {
            Text("Session Token Telemetry")
                .font(.headline)

            Chart(points) { point in
                BarMark(
                    x: .value("Category", point.label),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(AppSizes.radiusSmall)
            }
            .frame(minHeight: AppSizes.heightInspectorPanel)

            LabeledContent("Estimated Cost") {
                Text(totalCostUSD, format: .currency(code: "USD"))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(AppSpacing.card)
    }
}
