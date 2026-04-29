import SwiftUI
import AVFoundation

// MARK: - CheckInView

struct CheckInView: View {
    @State private var rollcalls: [Rollcall] = []
    @State private var isLoading = false
    @State private var checkInResults: [Int: RollcallCheckInResult] = [:]
    @State private var showManualEntry = false
    @State private var showQRScanner = false
    @State private var selectedRollcall: Rollcall? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            if !isLoading && rollcalls.isEmpty {
                ContentUnavailableView(
                    "目前沒有點名",
                    systemImage: "hand.raised.slash",
                    description: Text("向下滑動以重新整理")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(rollcalls) { rollcall in
                RollcallRowView(
                    rollcall: rollcall,
                    result: checkInResults[rollcall.rollcall_id],
                    onManualEntry: {
                        selectedRollcall = rollcall
                        showManualEntry = true
                    },
                    onRadarCheckIn: {
                        Task { await doRadarCheckIn(rollcall: rollcall) }
                    },
                    onQRCheckIn: {
                        selectedRollcall = rollcall
                        showQRScanner = true
                    }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .navigationTitle("課程簽到")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await loadRollcalls() }
        .refreshable { await loadRollcalls() }
        .alert("錯誤", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showManualEntry) {
            if let rollcall = selectedRollcall {
                ManualCheckInSheet(rollcall: rollcall) { code in
                    showManualEntry = false
                    Task { await doManualCheckIn(rollcall: rollcall, code: code) }
                }
            }
        }
        .sheet(isPresented: $showQRScanner) {
            if let rollcall = selectedRollcall {
                QRScannerSheet(rollcall: rollcall) { qrContent in
                    showQRScanner = false
                    Task { await doQRCheckIn(rollcall: rollcall, qrContent: qrContent) }
                }
            }
        }
    }

    private func loadRollcalls() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rollcalls = try await RollcallService.shared.fetchActiveRollcalls()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func doManualCheckIn(rollcall: Rollcall, code: String) async {
        do {
            let success = try await RollcallService.shared.manualCheckIn(rollcall: rollcall, code: code)
            checkInResults[rollcall.rollcall_id] = success ? .success(code) : .failure("數字碼錯誤，請再試一次")
        } catch {
            checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
        }
    }

    private func doRadarCheckIn(rollcall: Rollcall) async {
        do {
            let success = try await RollcallService.shared.radarCheckIn(
                rollcall: rollcall,
                latitude: 25.036238,
                longitude: 121.432292,
                accuracy: 50
            )
            checkInResults[rollcall.rollcall_id] = success ? .success(nil) : .failure("雷達點名失敗，可能不在教室範圍內")
        } catch {
            checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
        }
    }

    private func doQRCheckIn(rollcall: Rollcall, qrContent: String) async {
        do {
            let success = try await RollcallService.shared.qrCheckIn(rollcall: rollcall, qrContent: qrContent)
            checkInResults[rollcall.rollcall_id] = success ? .success(nil) : .failure("QR Code 點名失敗，請再試一次")
        } catch {
            checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Rollcall Row

private struct RollcallRowView: View {
    let rollcall: Rollcall
    let result: RollcallCheckInResult?
    let onManualEntry: () -> Void
    let onRadarCheckIn: () -> Void
    let onQRCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rollcall.course_title)
                        .font(.headline)
                    Text(rollcall.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(rollcall.created_by_name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(rollcall: rollcall)
            }

            HStack(spacing: 6) {
                Image(systemName: rollcall.is_number ? "number.circle.fill" : rollcall.is_qr ? "qrcode.viewfinder" : "location.circle.fill")
                    .font(.caption)
                Text(rollcall.is_number ? "數字碼點名" : rollcall.is_qr ? "QR Code 點名" : "雷達點名")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            if rollcall.isActive && !rollcall.isAlreadyCheckedIn {
                if let result {
                    resultView(result)
                } else if rollcall.is_number {
                    Button(action: onManualEntry) {
                        Label("輸入數字碼", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                } else if rollcall.is_qr {
                    Button(action: onQRCheckIn) {
                        Label("掃描 QR Code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                } else if rollcall.is_radar {
                    Button(action: onRadarCheckIn) {
                        Label("雷達簽到", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: RollcallCheckInResult) -> some View {
        switch result {
        case .success(let code):
            if let code {
                Label("簽到成功！數字碼：\(code)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Label("簽到成功！", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let rollcall: Rollcall

    private var label: (text: String, color: Color) {
        switch rollcall.status {
        case "on_call": return ("已簽到", .green)
        case "late":    return ("遲到",   .orange)
        default:
            if rollcall.is_expired { return ("已過期", .gray) }
            if rollcall.rollcall_status == "in_progress" { return ("進行中", .blue) }
            return ("缺席", .red)
        }
    }

    var body: some View {
        Text(label.text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(label.color.opacity(0.15))
            .foregroundStyle(label.color)
            .clipShape(Capsule())
    }
}

// MARK: - Manual Entry Sheet

struct ManualCheckInSheet: View {
    let rollcall: Rollcall
    let onConfirm: (String) -> Void

    @State private var code = ""
    @Environment(\.dismiss) private var dismiss

    private var paddedCode: String {
        String(repeating: "0", count: max(0, 4 - code.count)) + code
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 6) {
                    Text(rollcall.course_title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("請向教師確認點名數字碼")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("0000", text: $code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(4))
                    }
                    .padding()
                    .frame(maxWidth: 200)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    onConfirm(paddedCode)
                } label: {
                    Text("確認簽到")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .disabled(code.count != 4)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("手動輸入數字碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - QR Scanner Sheet

struct QRScannerSheet: View {
    let rollcall: Rollcall
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView(onScan: { code in
                    onScan(code)
                })
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text(rollcall.course_title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("請掃描教師顯示的 QR Code")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("掃描 QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - QR Scanner (AVFoundation)

private struct QRScannerView: UIViewControllerRepresentable {
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

final class ScannerViewController: UIViewController {
    var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { self.captureSession?.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        captureSession = session
    }
}

#Preview {
    NavigationStack {
        CheckInView()
    }
}
