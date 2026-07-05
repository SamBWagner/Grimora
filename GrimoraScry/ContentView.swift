import GrimoraCore
import GrimoraUI
import SwiftUI

struct ContentView: View {
  @Bindable var model: ScryHarnessModel

  var body: some View {
    Group {
      switch model.phase {
      case .loading:
        ProgressView("Opening card database…")
      case .downloadingCatalog(let status):
        VStack(spacing: 12) {
          ProgressView()
          Text(status)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      case .failed(let message):
        ContentUnavailableView(
          "Something broke",
          systemImage: "exclamationmark.triangle",
          description: Text(message)
        )
      case .ready:
        scanScreen
      }
    }
    .task { await model.launch() }
  }

  private var scanScreen: some View {
    ZStack {
      if model.camera.authorization == .denied {
        ContentUnavailableView(
          "Camera access denied",
          systemImage: "video.slash",
          description: Text("Enable the camera for Grimora Scry in Settings.")
        )
      } else {
        ScryCameraPreviewView(
          session: model.camera.session,
          detectedCards: model.camera.detectedCards,
          onFocusTap: { point in model.camera.focus(atDevicePoint: point) }
        )
        .ignoresSafeArea()
      }

      VStack {
        previewChip
        Spacer()
        controls
      }
      .padding()
    }
    .sheet(item: $model.pendingReview) { review in
      ReviewSheet(model: model, review: review)
        .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $model.showsCaptureList) {
      CaptureListView(model: model)
    }
    .statusBarHidden()
  }

  private var previewChip: some View {
    Group {
      if let guess = model.camera.previewGuess {
        Label(guess.name, systemImage: guess.confident ? "checkmark.seal.fill" : "questionmark.circle")
          .font(.headline)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule())
      }
    }
  }

  private var controls: some View {
    VStack(spacing: 14) {
      HStack(spacing: 10) {
        Toggle("Foil", isOn: $model.foil)
          .toggleStyle(.button)
        Toggle("Sleeved", isOn: $model.sleeved)
          .toggleStyle(.button)
        Picker("Background", selection: $model.background) {
          ForEach(ScryHarnessModel.backgroundOptions, id: \.self) { Text($0) }
        }
        .pickerStyle(.menu)
      }
      .font(.subheadline)
      .padding(8)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

      HStack {
        Button {
          model.showsCaptureList = true
        } label: {
          VStack(spacing: 2) {
            captureThumbnail
            Text("\(model.captures.count)")
              .font(.caption.bold())
          }
        }
        .buttonStyle(.plain)
        .frame(width: 64)

        Spacer()

        Button {
          Task { await model.scan() }
        } label: {
          if model.isScanning {
            ProgressView()
              .frame(width: 72, height: 72)
          } else {
            Image(systemName: "camera.viewfinder")
              .font(.system(size: 34))
              .frame(width: 72, height: 72)
          }
        }
        .background(Color.accentColor.opacity(0.85), in: Circle())
        .foregroundStyle(.white)
        .disabled(model.isScanning)

        Spacer()

        // Balances the thumbnail column so the shutter stays centered.
        Color.clear.frame(width: 64, height: 1)
      }
    }
  }

  private var captureThumbnail: some View {
    Group {
      if let latest = model.captures.first,
         let thumbnail = model.store.thumbnail(for: latest.id, maxPixel: 120) {
        Image(decorative: thumbnail, scale: 1)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo.stack")
          .font(.title3)
      }
    }
    .frame(width: 44, height: 44)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}
