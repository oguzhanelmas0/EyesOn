import CoreImage
import Foundation

/// Loads and applies the Metal-backed Gaussian eye warp CIWarpKernel.
/// Returns nil at initialisation if the Metal library or kernel is unavailable,
/// so callers can fall back gracefully without crashing.
final class EyeWarpKernel {

    static let shared: EyeWarpKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else {
            print("[EyeWarpKernel] ❌ default.metallib not found in bundle")
            return nil
        }
        print("[EyeWarpKernel] ✓ Found metallib at \(url.path)")
        guard let data = try? Data(contentsOf: url) else {
            print("[EyeWarpKernel] ❌ Cannot read metallib data")
            return nil
        }
        print("[EyeWarpKernel] ✓ Loaded \(data.count) bytes from metallib")
        do {
            let k = try CIWarpKernel(functionName: "gaussianEyeWarp",
                                     fromMetalLibraryData: data)
            print("[EyeWarpKernel] ✓ CIWarpKernel loaded successfully")
            return EyeWarpKernel(kernel: k)
        } catch {
            print("[EyeWarpKernel] ❌ CIWarpKernel init failed: \(error)")
            return nil
        }
    }()

    private let kernel: CIWarpKernel

    private init(kernel: CIWarpKernel) { self.kernel = kernel }

    /// Apply the Gaussian warp to `image`.
    /// - Parameters:
    ///   - pupilCenter: current iris centre in CIImage pixel coordinates (origin bottom-left)
    ///   - eyeCenter:   target iris position (eye socket centre) in the same space
    ///   - sigma:       Gaussian width in pixels — roughly 0.4 × eye width
    ///   - strength:    correction fraction; 1.0 = full correction, 0.0 = none
    func apply(
        to image: CIImage,
        pupilCenter: CGPoint,
        eyeCenter:   CGPoint,
        sigma:       CGFloat,
        strength:    CGFloat
    ) -> CIImage {
        // Expand the ROI so pixels outside the eye region can be sampled correctly
        let roiExpansion = sigma * 5
        return kernel.apply(
            extent: image.extent,
            roiCallback: { _, rect in
                rect.insetBy(dx: -roiExpansion, dy: -roiExpansion)
            },
            image: image,
            arguments: [
                CIVector(cgPoint: pupilCenter),
                CIVector(cgPoint: eyeCenter),
                Float(sigma),
                Float(strength)
            ]
        ) ?? image
    }
}
