import SwiftUI
import PhotosUI
import AVFoundation

/// SwiftUI wrapper for PHPickerViewController to select photos from library
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let maxSelections: Int
    let onImagesSelected: ([UIImage]) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = maxSelections
        config.filter = .images
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesSelected: onImagesSelected, onDismiss: onDismiss)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagesSelected: ([UIImage]) -> Void
        let onDismiss: () -> Void

        init(onImagesSelected: @escaping ([UIImage]) -> Void, onDismiss: @escaping () -> Void) {
            self.onImagesSelected = onImagesSelected
            self.onDismiss = onDismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard !results.isEmpty else {
                onDismiss()
                return
            }

            var selectedImages: [UIImage] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    defer { group.leave() }

                    if let error = error {
                        AppLogger.log("[PhotoPicker] Failed to load image: \(error.localizedDescription)")
                        return
                    }

                    if let image = object as? UIImage {
                        selectedImages.append(image)
                        AppLogger.log("[PhotoPicker] Loaded image: \(image.size)")
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                if selectedImages.isEmpty {
                    self?.onDismiss()
                } else {
                    AppLogger.log("[PhotoPicker] Selected \(selectedImages.count) images")
                    self?.onImagesSelected(selectedImages)
                }
            }
        }
    }
}

/// SwiftUI wrapper for UIImagePickerController for camera capture
struct CameraImagePicker: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void
        let onDismiss: () -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
            self.onImageCaptured = onImageCaptured
            self.onDismiss = onDismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)

            if let image = info[.originalImage] as? UIImage {
                AppLogger.log("[CameraPicker] Captured image: \(image.size)")
                onImageCaptured(image)
            } else {
                AppLogger.log("[CameraPicker] No image in picker result")
                onDismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            AppLogger.log("[CameraPicker] Cancelled")
            onDismiss()
        }
    }
}

// MARK: - Camera Availability Check

extension CameraImagePicker {
    /// Check if camera is available on this device
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Check camera authorization status
    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Request camera permission
    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

// MARK: - Preview

#Preview("Photo Library Picker") {
    PhotoLibraryPicker(
        maxSelections: 4,
        onImagesSelected: { images in
            print("Selected \(images.count) images")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
}
