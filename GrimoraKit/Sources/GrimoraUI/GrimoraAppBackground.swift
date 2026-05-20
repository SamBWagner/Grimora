import SwiftUI

struct GrimoraAppBackground: View {
    var palette: GrimoraPalette

    var body: some View {
        palette.appBackground.color
            .ignoresSafeArea()
    }
}
