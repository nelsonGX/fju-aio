import SwiftUI
import AVFoundation
import UIKit

// MARK: - QRScannerView
// Reusable AVFoundation-backed QR code scanner view.
// Used in CheckInView, FriendListView, and GroupRollcallView.

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue else { return }
            hasScanned = true
            DispatchQueue.main.async { self.onScan(value) }
        }
    }
}

// MARK: - ScannerViewController

final class ScannerViewController: UIViewController {
    var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var issueView: UIView?
    private var hasPresentedCameraAlert = false
    /// True after setupCamera() has configured the session but before startRunning() is called.
    /// startRunning() is deferred to viewDidLayoutSubviews so the preview layer has a real frame.
    private var pendingStart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Resume a previously set up session (e.g. returning from background)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if captureSession == nil {
            // Defer setup until viewDidAppear so the view is fully in the window hierarchy,
            // which is required for AVCaptureVideoPreviewLayer to display correctly.
            checkCameraPermissionAndSetup()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pendingStart = false
        captureSession?.stopRunning()
        // Tear down the session completely so the next presentation starts fresh.
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        captureSession = nil
        hasPresentedCameraAlert = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        // Start the session here instead of in setupCamera() so we are guaranteed
        // to have a real (non-zero) frame before the preview layer becomes visible.
        if pendingStart, let session = captureSession, !session.isRunning {
            pendingStart = false
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }
    }

    private func checkCameraPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.setupCamera()
                    } else {
                        self.showCameraPermissionIssue()
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionIssue()
        @unknown default:
            showCameraPermissionIssue()
        }
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showCameraUnavailableIssue()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showCameraUnavailableIssue()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        captureSession = session
        issueView?.removeFromSuperview()
        issueView = nil
        // Defer startRunning() to viewDidLayoutSubviews so the preview layer has a
        // real frame (non-zero bounds) before the session starts producing frames.
        pendingStart = true
    }

    private func showCameraPermissionIssue() {
        showIssueView(
            systemImage: "camera.fill",
            title: "無法使用相機",
            message: "請在「設定」中允許此 App 使用相機。",
            showsSettingsButton: true
        )
        presentCameraPermissionAlertIfNeeded()
    }

    private func showCameraUnavailableIssue() {
        showIssueView(
            systemImage: "camera.fill",
            title: "無法啟動相機",
            message: "請確認相機可用後再試一次。",
            showsSettingsButton: false
        )
        presentCameraUnavailableAlertIfNeeded()
    }

    private func showIssueView(systemImage: String, title: String, message: String, showsSettingsButton: Bool) {
        issueView?.removeFromSuperview()

        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .center
        container.spacing = 10
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: UIImage(systemName: systemImage))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 44),
            imageView.heightAnchor.constraint(equalToConstant: 44)
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        container.addArrangedSubview(imageView)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(messageLabel)

        if showsSettingsButton {
            let button = UIButton(type: .system)
            button.setTitle("前往設定", for: .normal)
            button.addAction(UIAction { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }, for: .touchUpInside)
            container.addArrangedSubview(button)
        }

        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
        issueView = container
    }

    private func presentCameraPermissionAlertIfNeeded() {
        guard !hasPresentedCameraAlert, presentedViewController == nil else { return }
        hasPresentedCameraAlert = true
        let alert = UIAlertController(
            title: "無法使用相機",
            message: "請在「設定」中允許此 App 使用相機。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "前往設定", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }

    private func presentCameraUnavailableAlertIfNeeded() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "無法啟動相機",
            message: "請確認相機可用後再試一次。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "確定", style: .cancel))
        present(alert, animated: true)
    }
}
