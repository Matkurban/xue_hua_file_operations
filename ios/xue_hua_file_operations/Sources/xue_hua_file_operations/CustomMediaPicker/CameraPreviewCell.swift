import AVFoundation
import UIKit

/// Collection view cell rendering a live rear-camera preview in the top-left
/// 1x2 grid slot. All AVCaptureSession lifecycle calls run strictly on a
/// dedicated background serial queue so the main thread is never blocked.
/// 渲染在媒体网格左上角 1×2 位置的实时后置相机预览单元格。
/// 所有 AVCaptureSession 启停操作均严格在后台串行队列执行，绝不阻塞主线程。
final class CameraPreviewCell: UICollectionViewCell {
    static let reuseId = "XueHuaCameraPreviewCell"

    private let sessionQueue = DispatchQueue(label: "com.kurban.xue_hua_file_operations.camera_tile")
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isStopped = false

    private let fallbackStack = UIStackView()
    private let fallbackIcon = UIImageView()
    private let fallbackLabel = UILabel()
    private let cornerBadge = UIView()
    private let cornerIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor(red: 0.13, green: 0.14, blue: 0.15, alpha: 1.0)
        contentView.clipsToBounds = true
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        fallbackStack.axis = .vertical
        fallbackStack.alignment = .center
        fallbackStack.spacing = 6
        fallbackStack.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        fallbackIcon.image = UIImage(systemName: "camera.fill", withConfiguration: iconConfig)
        fallbackIcon.tintColor = .white
        fallbackStack.addArrangedSubview(fallbackIcon)

        fallbackLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fallbackLabel.textColor = .white
        fallbackStack.addArrangedSubview(fallbackLabel)

        contentView.addSubview(fallbackStack)
        NSLayoutConstraint.activate([
            fallbackStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            fallbackStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        cornerBadge.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        cornerBadge.layer.cornerRadius = 16
        cornerBadge.translatesAutoresizingMaskIntoConstraints = false
        cornerBadge.isHidden = true
        contentView.addSubview(cornerBadge)

        let badgeConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        cornerIcon.image = UIImage(systemName: "camera.fill", withConfiguration: badgeConfig)
        cornerIcon.tintColor = .white
        cornerIcon.translatesAutoresizingMaskIntoConstraints = false
        cornerBadge.addSubview(cornerIcon)

        NSLayoutConstraint.activate([
            cornerBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cornerBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            cornerBadge.widthAnchor.constraint(equalToConstant: 32),
            cornerBadge.heightAnchor.constraint(equalToConstant: 32),
            cornerIcon.centerXAnchor.constraint(equalTo: cornerBadge.centerXAnchor),
            cornerIcon.centerYAnchor.constraint(equalTo: cornerBadge.centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = contentView.bounds
    }

    /// Configures label and starts live camera preview if camera permission is
    /// already granted and a physical camera device exists.
    /// 配置文案并在已获得相机权限且存在摄像头设备时启动实时预览。
    func configure(cameraLabel: String) {
        isStopped = false
        fallbackLabel.text = cameraLabel
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            showFallback()
            return
        }
        startLiveSessionIfNeeded()
    }

    private func showFallback() {
        fallbackStack.isHidden = false
        cornerBadge.isHidden = true
    }

    private func startLiveSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isStopped else { return }
            if let session = self.captureSession {
                if !session.isRunning {
                    session.startRunning()
                }
                return
            }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { self.showFallback() }
                return
            }

            let session = AVCaptureSession()
            session.sessionPreset = .medium
            guard session.canAddInput(input) else {
                DispatchQueue.main.async { self.showFallback() }
                return
            }
            session.addInput(input)
            self.captureSession = session

            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isStopped else { return }
                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.contentView.bounds
                self.contentView.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
                self.fallbackStack.isHidden = true
                self.cornerBadge.isHidden = false
            }

            if !self.isStopped {
                session.startRunning()
            }
        }
    }

    /// Stops the live capture session asynchronously without blocking the main thread.
    /// 在后台串行队列异步停止相机预览会话，绝不阻塞主线程。
    func stopSession() {
        isStopped = true
        let session = captureSession
        sessionQueue.async {
            if let session = session, session.isRunning {
                session.stopRunning()
            }
        }
    }

    deinit {
        // Capture session by value and stop on background queue to prevent main-thread deadlock.
        // 按值捕获 session 并在后台队列停止，避免 deinit 在主线程同步 stopRunning 引发卡死。
        let session = captureSession
        let queue = sessionQueue
        queue.async {
            if let session = session, session.isRunning {
                session.stopRunning()
            }
        }
    }
}
