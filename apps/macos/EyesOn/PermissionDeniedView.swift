import SwiftUI
import AppKit

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 56))
                .foregroundColor(.red.opacity(0.8))

            Text("Kamera Erişimi Gerekli")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("EyesOn'un çalışabilmesi için kamera iznine ihtiyacı var.\nSistem Ayarları > Gizlilik ve Güvenlik > Kamera bölümünden etkinleştirebilirsin.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button(action: openPrivacySettings) {
                Label("Sistem Ayarlarını Aç", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
        }
        .padding(48)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}
