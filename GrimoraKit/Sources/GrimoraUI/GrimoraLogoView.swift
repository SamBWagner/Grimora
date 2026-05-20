import SwiftUI

struct GrimoraLogoView: View {
    var size: CGFloat

    var body: some View {
        Image("GrimoraLogo", bundle: .module)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .accessibilityHidden(true)
    }
}
