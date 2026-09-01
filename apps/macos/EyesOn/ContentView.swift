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
        VStack(spacing: 0) {
            // Video + overlays
            ZStack(alignment: .bottomTrailing) {
                frameView

                // Debug overlay — always on top when enabled (correction state irrelevant)
                if viewModel.debugOverlayEnabled {
                    LandmarkDebugOverlay(
                        observations:     viewModel.faceObservations,
                        frameSize:        viewModel.frameSize,
                        gazeEstimate:     viewModel.gazeEstimate,
                        validationResult: viewModel.validationResult,
                        showFaceBox:      viewModel.showFaceBox,
                        showLandmarks:    viewModel.showLandmarks,
                        showEyeROI:       viewModel.showEyeROI
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
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

                // Bottom-right HUD
                VStack(alignment: .trailing, spacing: 10) {
                    GazeDirectionView(direction: viewModel.gazeDirection)
                    correctionToggle
                }
                .padding(16)
            }

            // Debug control bar
            debugControlBar
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

    // MARK: - Debug control bar

    private var debugControlBar: some View {
        HStack(spacing: 12) {
            debugToggle("🐞 Debug",  binding: $viewModel.debugOverlayEnabled, tint: .purple)
            if viewModel.debugOverlayEnabled {
                Divider().frame(height: 16)
                debugToggle("□ Yüz",    binding: $viewModel.showFaceBox,   tint: .green)
                debugToggle("□ Marks",  binding: $viewModel.showLandmarks,  tint: .cyan)
                debugToggle("□ ROI",    binding: $viewModel.showEyeROI,     tint: .cyan)
                Divider().frame(height: 16)
            }
            debugToggle("⚡ Düzeltme", binding: $viewModel.correctionEnabled, tint: .yellow)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.85))
    }

    private func debugToggle(_ title: String, binding: Binding<Bool>, tint: Color) -> some View {
        Button {
            binding.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(binding.wrappedValue ? tint : .gray)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(binding.wrappedValue ? tint.opacity(0.18) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared

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
                Text(viewModel.isCorrecting   ? "Düzeltiyor ✓" :
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
