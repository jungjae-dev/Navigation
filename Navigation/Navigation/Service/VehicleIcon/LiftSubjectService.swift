import UIKit
import Vision
import PhotosUI

/// Uses Vision framework to remove background from a photo, producing a cutout for use as a vehicle icon
@available(iOS 17.0, *)
final class LiftSubjectService {

    // MARK: - Errors

    enum LiftSubjectError: LocalizedError {
        case noImageProvided
        case maskGenerationFailed
        case imageProcessingFailed

        var errorDescription: String? {
            switch self {
            case .noImageProvided:
                return "이미지가 제공되지 않았습니다."
            case .maskGenerationFailed:
                return "배경 제거에 실패했습니다."
            case .imageProcessingFailed:
                return "이미지 처리에 실패했습니다."
            }
        }
    }

    // MARK: - Public

    /// Remove background from image using Vision framework's foreground instance mask
    func liftSubject(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw LiftSubjectError.noImageProvided
        }

        // Create foreground instance mask request
        let request = VNGenerateForegroundInstanceMaskRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw LiftSubjectError.maskGenerationFailed
        }

        // Generate mask pixel buffer for the foreground instances
        let allInstances = result.allInstances
        let maskPixelBuffer = try result.generateScaledMaskForImage(
            forInstances: allInstances,
            from: handler
        )

        // Apply mask to original image
        let maskedImage = try applyMask(maskPixelBuffer, to: cgImage)
        return maskedImage
    }

    // MARK: - Private

    private func applyMask(_ maskBuffer: CVPixelBuffer, to originalImage: CGImage) throws -> UIImage {
        let maskWidth = CVPixelBufferGetWidth(maskBuffer)
        let maskHeight = CVPixelBufferGetHeight(maskBuffer)

        // Create CIImage from mask
        let maskCIImage = CIImage(cvPixelBuffer: maskBuffer)

        // Scale original image to mask dimensions
        let originalCIImage = CIImage(cgImage: originalImage)
        let scaleX = CGFloat(maskWidth) / CGFloat(originalImage.width)
        let scaleY = CGFloat(maskHeight) / CGFloat(originalImage.height)
        let scaledOriginal = originalCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Use CIBlendWithMask to composite foreground over transparent background
        let clearBackground = CIImage.empty()
            .cropped(to: CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight))

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw LiftSubjectError.imageProcessingFailed
        }

        blendFilter.setValue(scaledOriginal, forKey: kCIInputImageKey)
        blendFilter.setValue(clearBackground, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskCIImage, forKey: kCIInputMaskImageKey)

        guard let outputCIImage = blendFilter.outputImage else {
            throw LiftSubjectError.imageProcessingFailed
        }

        // Render to UIImage
        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) else {
            throw LiftSubjectError.imageProcessingFailed
        }

        return UIImage(cgImage: outputCGImage)
    }
}

// MARK: - Photo Picker Helper

/// Wraps PHPickerViewController for selecting a single image
final class PhotoPickerHelper: NSObject, PHPickerViewControllerDelegate {

    private var completion: ((UIImage?) -> Void)?

    /// Present photo picker and return selected image
    func pickImage(from viewController: UIViewController, completion: @escaping (UIImage?) -> Void) {
        self.completion = completion

        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        viewController.present(picker, animated: true)
    }

    // MARK: - PHPickerViewControllerDelegate

    nonisolated func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        MainActor.assumeIsolated {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                self.completion?(nil)
                self.completion = nil
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                DispatchQueue.main.async {
                    self?.completion?(image as? UIImage)
                    self?.completion = nil
                }
            }
        }
    }
}
