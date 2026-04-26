import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation
import UIKit

struct QRSheet: View {
    let pubkeyHex: String
    var onScannedPubkey: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nuruTheme) private var theme

    @State private var mode: QRMode = .display
    @State private var scannedText: String = ""
    @State private var scannerError: String? = nil
    @State private var scanResetToken = UUID()

    private enum QRMode: String, CaseIterable, Identifiable {
        case display = "表示"
        case scan = "スキャン"
        var id: String { rawValue }
    }

    private var npub: String {
        guard let bytes = Data(hexString: pubkeyHex).map({ Array($0) }) else { return pubkeyHex }
        return NostrKeyUtils.encodeNpub(bytes) ?? pubkeyHex
    }

    /// スキャン文字列からプロフィール pubkey(hex) を抽出
    private func extractProfilePubkey(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if trimmed.hasPrefix("nostr:") {
            payload = String(trimmed.dropFirst("nostr:".count))
        } else {
            payload = trimmed
        }

        if let parsed = NostrBech32.decode(payload) {
            switch parsed.type {
            case .npub, .nprofile:
                return parsed.hex
            default:
                break
            }
        }

        if let bytes = NostrKeyUtils.parsePublicKey(payload) {
            return NostrKeyUtils.bytesToHex(bytes)
        }

        // hex pubkey 直書き
        if payload.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil {
            return payload.lowercased()
        }

        return nil
    }

    private var qrImage: Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("nostr:\(npub)".utf8)
        filter.correctionLevel = "M"

        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(cg, scale: 1, label: Text("QR Code"))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: "QRコード", onDismiss: { dismiss() }) {
                Color.clear.frame(width: 40, height: 40)
            }

            Picker("モード", selection: $mode) {
                ForEach(QRMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            if mode == .display { displaySection } else { scanSection }

            Spacer()
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .onChange(of: scannedText) { _, value in
            guard !value.isEmpty else { return }
            guard let pk = extractProfilePubkey(from: value) else { return }
            onScannedPubkey?(pk)
            dismiss()
        }
    }

    private var displaySection: some View {
        VStack(spacing: 20) {
            if let img = qrImage {
                img
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .frame(width: 240, height: 240)
                    .overlay(ProgressView().tint(.black))
            }

            Text(String(npub.prefix(20)) + "...")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 12) {
                Button("閉じる") { dismiss() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(theme.textSecondary)

                Button {
                    let text = "nostr:\(npub)"
                    UIPasteboard.general.string = text
                    let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(av, animated: true)
                    }
                } label: {
                    Label("共有", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(NuruColors.lineGreen)
            }
        }
        .padding(.horizontal, 32)
    }

    private var scanSection: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(height: 280)

                QRScannerView(scannedText: $scannedText, errorText: $scannerError)
                    .id(scanResetToken)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(height: 280)
            }
            .padding(.horizontal, 20)

            if let err = scannerError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            if !scannedText.isEmpty {
                Text(scannedText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button("コピー") { UIPasteboard.general.string = scannedText }
                        .buttonStyle(.bordered)

                    Button("開く") {
                        if let url = URL(string: scannedText), UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NuruColors.lineGreen)

                    Button("再スキャン") {
                        scannedText = ""
                        scannerError = nil
                        scanResetToken = UUID()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct QRScannerView: UIViewRepresentable {
    @Binding var scannedText: String
    @Binding var errorText: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(scannedText: $scannedText, errorText: $errorText)
    }

    func makeUIView(context: Context) -> ScannerPreviewView {
        let view = ScannerPreviewView()
        context.coordinator.attachPreview(to: view)
        context.coordinator.startIfPossible()
        return view
    }

    func updateUIView(_ uiView: ScannerPreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: ScannerPreviewView, coordinator: Coordinator) {
        coordinator.stopSession()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private weak var previewView: ScannerPreviewView?
        private var didConfigure = false

        @Binding var scannedText: String
        @Binding var errorText: String?

        init(scannedText: Binding<String>, errorText: Binding<String?>) {
            _scannedText = scannedText
            _errorText = errorText
        }

        func attachPreview(to view: ScannerPreviewView) {
            previewView = view
            view.previewLayer.videoGravity = .resizeAspectFill
            view.previewLayer.session = session
        }

        func startIfPossible() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureAndStart()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted { self.configureAndStart() }
                        else { self.errorText = "カメラの使用が許可されていません" }
                    }
                }
            default:
                errorText = "設定でカメラアクセスを許可してください"
            }
        }

        private func configureAndStart() {
            guard !didConfigure else { startSession(); return }

            guard let device = AVCaptureDevice.default(for: .video) else {
                errorText = "カメラが利用できません"
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }

                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    output.metadataObjectTypes = [.qr]
                }

                didConfigure = true
                startSession()
            } catch {
                errorText = "カメラ初期化に失敗しました"
            }
        }

        private func startSession() {
            DispatchQueue.global(qos: .userInitiated).async {
                if !self.session.isRunning { self.session.startRunning() }
            }
        }

        func stopSession() {
            DispatchQueue.global(qos: .userInitiated).async {
                if self.session.isRunning { self.session.stopRunning() }
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr,
                  let value = obj.stringValue,
                  !value.isEmpty else { return }
            scannedText = value
            stopSession()
        }
    }
}

private final class ScannerPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private extension Data {
    init?(hexString hex: String) {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }
}
