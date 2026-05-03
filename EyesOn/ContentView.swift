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
                runningView
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

    // MARK: - Running state

    @ViewBuilder
    private var runningView: some View {
        ZStack(alignment: .bottomTrailing) {
            // Processed (or raw) video frame
            frameView

            // Landmark overlay: only when correction is OFF
            // (when ON, shifted pixels make the original landmarks appear misaligned)
            if !viewModel.correctionEnabled {
                FaceOverlayView(
                    observations: viewModel.faceObservations,
                    frameSize: viewModel.frameSize
                )
                .ignoresSafeArea()
            }

            // Top: active correction banner OR rejection reason
            VStack {
                if viewModel.isCorrecting {
                    statusPill("⚡ Göz teması düzeltiliyor", color: .green)
                } else if viewModel.correctionEnabled && !viewModel.isCorrectionSafe,
                          let reason = viewModel.rejectionReason {
                    statusPill("⚠ \(reason)", color: .orange)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .allowsHitTesting(false)

            // Bottom-left: landmark validation debug text
            VStack {
                Spacer()
                HStack {
                    if let debug = viewModel.validationResult?.debugText {
                        Text(debug)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(viewModel.isCorrectionSafe ? .green : .orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6))
                            .cornerRadius(6)
                    }
                    Spacer()
                }
                .padding(.leading, 10)
                .padding(.bottom, 10)
            }
            .allowsHitTesting(false)

            // Bottom-right HUD
            VStack(alignment: .trailing, spacing: 10) {
                GazeDirectionView(direction: viewModel.gazeDirection)
                correctionToggle
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var frameView: some View {
        if let frame = viewModel.processedFrame {
            Image(nsImage: frame)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.88))
            .clipShape(Capsule())
    }

    private var correctionToggle: some View {
        Button {
            viewModel.correctionEnabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.correctionEnabled ? "eye.fill" : "eye.slash.fill")
                Text(viewModel.isCorrecting  ? "Düzeltiyor ✓" :
                     viewModel.correctionEnabled ? "Düzeltme Açık" : "Düzeltme Kapalı")
            }
            .font(.caption.bold())
            .foregroundColor(viewModel.isCorrecting ? .green :
                             viewModel.correctionEnabled ? .white : .gray)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(viewModel.isCorrecting ? .black.opacity(0.8) : .black.opacity(0.65))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(viewModel.isCorrecting ? Color.green : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Other states

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.4).tint(.white)
            Text("Kamera başlatılıyor...")
                .foregroundColor(.gray).font(.subheadline)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash").font(.system(size: 48)).foregroundColor(.orange)
            Text("Kamera Bulunamadı").font(.headline).foregroundColor(.white)
            Text("Lütfen bir webcam bağlayıp uygulamayı yeniden başlatın.")
                .foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
