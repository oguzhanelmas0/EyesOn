import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.cameraState {
            case .loading:
                loadingView

            case .running:
                cameraWithOverlay

            case .denied:
                PermissionDeniedView()

            case .unavailable:
                unavailableView
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear  { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    @ViewBuilder
    private var cameraWithOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            // Camera feed + landmark overlay
            ZStack {
                CameraPreviewView(session: viewModel.captureSession)
                    .ignoresSafeArea()

                FaceOverlayView(
                    observations: viewModel.faceObservations,
                    frameSize: viewModel.frameSize
                )
                .ignoresSafeArea()
            }

            // Gaze direction HUD (bottom-right corner)
            GazeDirectionView(direction: viewModel.gazeDirection)
                .padding(16)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(.white)
            Text("Kamera başlatılıyor...")
                .foregroundColor(.gray)
                .font(.subheadline)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Kamera Bulunamadı")
                .font(.headline)
                .foregroundColor(.white)
            Text("Lütfen bir webcam bağlayıp uygulamayı yeniden başlatın.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
