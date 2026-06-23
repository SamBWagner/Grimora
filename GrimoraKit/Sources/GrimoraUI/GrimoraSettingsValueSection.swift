import GrimoraCore
import SwiftUI

/// "Value Display" settings section: the display-currency picker, backed by the
/// shared value preferences.
struct GrimoraSettingsValueSection: View {
    @AppStorage(GrimoraValuePreferences.displayCurrencyKey)
    private var valueDisplayCurrencyRawValue = CardValueDisplayCurrency.usd.rawValue

    var body: some View {
        Section("Value Display") {
            Picker("Currency", selection: valueDisplayCurrency) {
                ForEach(CardValueDisplayCurrency.allCases) { currency in
                    Text(currency.title).tag(currency)
                }
            }
            .accessibilityIdentifier("value-currency-picker")

            Text("Non-USD values are converted from USD with a cached daily exchange rate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var valueDisplayCurrency: Binding<CardValueDisplayCurrency> {
        Binding {
            GrimoraValuePreferences.displayCurrency(from: valueDisplayCurrencyRawValue)
        } set: { newValue in
            valueDisplayCurrencyRawValue = newValue.rawValue
        }
    }
}
