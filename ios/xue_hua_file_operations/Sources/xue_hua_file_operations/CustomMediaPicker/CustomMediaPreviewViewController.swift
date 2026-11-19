import AVFoundation
import Photos
import UIKit

/// Full-screen native media preview controller for iOS supporting horizontal
/// paging, high-resolution image display, inline video playback, and live
/// selection synchronization with the main picker grid.
/// iOS 原生全屏媒体预览控制器，支持横向分页滑动、高清图片显示、视频内联播放
/// 以及与主网格实时同步的勾选状态。
final class CustomMediaPreviewViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{
    private let config: CustomMediaPickerConfig
    private let repository: PhotoLibraryRepository
    private let assets: PHFetchResult<PHAsset>
    private var currentIndex: Int
    private let selectedIdsProvider: () -> [String]
    private let onToggleSelection: (PHAsset) -> Bool
    private let onConfirmSelection: () -> Void

    private var collectionView: UICollectionView!
    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private let selectBadgeButton = UIButton(type: .custom)
    private let bottomBar = UIView()
    private let confirmButton = UIButton(type: .system)

    private var activePlayer: AVPlayer?
    private var activePlayerLayer: AVPlayerLayer?
    private var hasScrolledToInitial = false

    init(
        config: CustomMediaPickerConfig,
        repository: PhotoLibraryRepository,
        assets: PHFetchResult<PHAsset>,
        initialIndex: Int,
        selectedIdsProvider: @escaping () -> [String],
        onToggleSelection: @escaping (PHAsset) -> Bool,
        onConfirmSelection: @escaping () -> Void
    ) {
        self.config = config
        self.repository = repository
        self.assets = assets
        self.currentIndex = min(max(0, initialIndex), max(0, assets.count - 1))
        self.selectedIdsProvider = selectedIdsProvider
        self.onToggleSelection = onToggleSelection
        self.onConfirmSelection = onConfirmSelection
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCollectionView()
        setupTopBar()
        setupBottomBar()
        refreshControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasScrolledToInitial, assets.count > 0 {
            hasScrolledToInitial = true
            let indexPath = IndexPath(item: currentIndex, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopActiveVideo()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PreviewAssetCell.self, forCellWithReuseIdentifier: PreviewAssetCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupTopBar() {
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        let backConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        backButton.layer.cornerRadius = 20
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(handleBack), for: .touchUpInside)
        topBar.addSubview(backButton)

        counterLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        counterLabel.textColor = .white
        counterLabel.textAlignment = .center
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(counterLabel)

        selectBadgeButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        selectBadgeButton.layer.cornerRadius = 15
        selectBadgeButton.translatesAutoresizingMaskIntoConstraints = false
        selectBadgeButton.addTarget(self, action: #selector(handleToggleSelect), for: .touchUpInside)
        topBar.addSubview(selectBadgeButton)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
            backButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),

            counterLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            counterLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),

            selectBadgeButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            selectBadgeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            selectBadgeButton.widthAnchor.constraint(equalToConstant: 30),
            selectBadgeButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func setupBottomBar() {
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        confirmButton.backgroundColor = config.theme.primaryColor
        confirmButton.setTitleColor(config.theme.onPrimaryColor, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        confirmButton.layer.cornerRadius = 20
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(handleConfirm), for: .touchUpInside)
        bottomBar.addSubview(confirmButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            confirmButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            confirmButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    @objc private func handleBack() {
        dismiss(animated: true)
    }

    @objc private func handleToggleSelect() {
        guard currentIndex < assets.count else { return }
        let asset = assets.object(at: currentIndex)
        if onToggleSelection(asset) {
            refreshControls()
        }
    }

    @objc private func handleConfirm() {
        let ids = selectedIdsProvider()
        if !config.multiple, ids.isEmpty, currentIndex < assets.count {
            _ = onToggleSelection(assets.object(at: currentIndex))
        }
        if !selectedIdsProvider().isEmpty {
            dismiss(animated: false) {
                self.onConfirmSelection()
            }
        }
    }

    private func stopActiveVideo() {
        activePlayer?.pause()
        activePlayer = nil
        activePlayerLayer?.removeFromSuperlayer()
        activePlayerLayer = nil
    }

    private func refreshControls() {
        counterLabel.text = "\(currentIndex + 1) / \(assets.count)"
        let ids = selectedIdsProvider()
        let currentId = currentIndex < assets.count ? assets.object(at: currentIndex).localIdentifier : ""
        if let idx = ids.firstIndex(of: currentId) {
            selectBadgeButton.backgroundColor = config.theme.primaryColor
            selectBadgeButton.layer.borderWidth = 0
            selectBadgeButton.setTitleColor(config.theme.onPrimaryColor, for: .normal)
            selectBadgeButton.setTitle(config.multiple ? "\(idx + 1)" : "✓", for: .normal)
        } else {
            selectBadgeButton.backgroundColor = config.theme.unselectedBadgeFillColor
            selectBadgeButton.layer.borderWidth = 2
            selectBadgeButton.layer.borderColor = config.theme.unselectedBadgeBorderColor.cgColor
            selectBadgeButton.setTitle("", for: .normal)
        }

        let count = ids.count
        let title = count > 0 ? "\(config.strings.done) (\(count))" : config.strings.done
        confirmButton.setTitle(title, for: .normal)
        confirmButton.alpha = (count > 0 || !config.multiple) ? 1.0 : 0.5
    }

    // MARK: - UICollectionViewDataSource & Delegate

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        assets.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PreviewAssetCell.reuseId,
            for: indexPath
        ) as? PreviewAssetCell else {
            return UICollectionViewCell()
        }
        let asset = assets.object(at: indexPath.item)
        cell.configure(asset: asset, repository: repository) { [weak self, weak cell] in
            guard let self = self, let cell = cell else { return }
            self.playVideo(asset: asset, in: cell)
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentIndexFromScroll()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { updateCurrentIndexFromScroll() }
    }

    private func updateCurrentIndexFromScroll() {
        let width = max(1, collectionView.bounds.width)
        let page = Int(round(collectionView.contentOffset.x / width))
        if page >= 0, page < assets.count, page != currentIndex {
            stopActiveVideo()
            currentIndex = page
            refreshControls()
        }
    }

    private func playVideo(asset: PHAsset, in cell: PreviewAssetCell) {
        stopActiveVideo()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self, weak cell] playerItem, _ in
            guard let self = self, let cell = cell, let playerItem = playerItem else { return }
            DispatchQueue.main.async {
                let player = AVPlayer(playerItem: playerItem)
                let layer = AVPlayerLayer(player: player)
                layer.frame = cell.contentView.bounds
                layer.videoGravity = .resizeAspect
                cell.contentView.layer.addSublayer(layer)
                cell.setPlayButtonHidden(true)
                self.activePlayer = player
                self.activePlayerLayer = layer
                player.play()
            }
        }
    }
}

/// Full-screen preview cell showing a single image or video cover + play button.
/// 全屏预览单元格：展示单张高清图或视频封面及播放按钮。
private final class PreviewAssetCell: UICollectionViewCell {
    static let reuseId = "XueHuaPreviewAssetCell"

    private let imageView = UIImageView()
    private let playButton = UIButton(type: .system)
    private var requestId: PHImageRequestID = PHInvalidImageRequestID
    private var onPlay: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: iconConfig), for: .normal)
        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        playButton.layer.cornerRadius = 32
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(handlePlay), for: .touchUpInside)
        contentView.addSubview(playButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            playButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 64),
            playButton.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if requestId != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestId)
            requestId = PHInvalidImageRequestID
        }
        imageView.image = nil
        playButton.isHidden = true
        onPlay = nil
    }

    func configure(
        asset: PHAsset,
        repository: PhotoLibraryRepository,
        onPlay: @escaping () -> Void
    ) {
        self.onPlay = onPlay
        playButton.isHidden = asset.mediaType != .video
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: UIScreen.main.bounds.height * scale
        )
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        requestId = repository.imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                if let image = image {
                    self?.imageView.image = image
                }
            }
        }
    }

    func setPlayButtonHidden(_ hidden: Bool) {
        playButton.isHidden = hidden
    }

    @objc private func handlePlay() {
        onPlay?()
    }
}
