import AVFoundation
import Photos
import UIKit

/// Full-screen immersive native media preview controller for iOS.
/// Features unified zoom/fade entrance & exit animations, pinch & double-tap zoom,
/// tap-to-toggle chrome, soft gradient top/bottom bars, a horizontal selected-media
/// thumbnail strip, inline video playback, and a sleek floating toast pill.
///
/// iOS 原生沉浸式全屏媒体预览控制器。
/// 支持与 Android 一致的平滑缩放淡入/淡出动画、双指与双击缩放、轻触切换工具栏显隐、
/// 柔和渐变顶/底栏、底部已选缩略图快速跳转条、视频内联播放及精致悬浮 Toast 提示。
final class CustomMediaPreviewViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{
    private let config: CustomMediaPickerConfig
    private let repository: PhotoLibraryRepository
    private let assets: PHFetchResult<PHAsset>
    private var currentIndex: Int
    private let selectedIdsProvider: () -> [String]
    private let selectedAssetsProvider: () -> [PHAsset]
    private let onToggleSelection: (PHAsset) -> Bool
    private let onConfirmSelection: () -> Void

    private let contentContainer = UIView()
    private var collectionView: UICollectionView!
    private let topChrome = UIView()
    private let backButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private let selectBadgeHitButton = UIButton(type: .custom)
    private let selectBadgeCircle = UIView()
    private let selectBadgeNumber = UILabel()
    private let selectBadgeCheck = UIImageView()

    private let bottomChrome = UIView()
    private var stripCollectionView: UICollectionView!
    private var stripHeightConstraint: NSLayoutConstraint!
    private var lastRenderedStripIds: [String] = []
    private let confirmButton = UIButton(type: .system)

    private var activePlayer: AVPlayer?
    private var activePlayerLayer: AVPlayerLayer?
    private var hasScrolledToInitial = false
    private var hasAnimatedEntrance = false
    private var isChromeVisible = true
    private var isDismissing = false

    private let toastContainer = UIView()
    private let toastLabel = UILabel()
    private var toastHideWorkItem: DispatchWorkItem?

    init(
        config: CustomMediaPickerConfig,
        repository: PhotoLibraryRepository,
        assets: PHFetchResult<PHAsset>,
        initialIndex: Int,
        selectedIdsProvider: @escaping () -> [String],
        selectedAssetsProvider: @escaping () -> [PHAsset],
        onToggleSelection: @escaping (PHAsset) -> Bool,
        onConfirmSelection: @escaping () -> Void
    ) {
        self.config = config
        self.repository = repository
        self.assets = assets
        self.currentIndex = min(max(0, initialIndex), max(0, assets.count - 1))
        self.selectedIdsProvider = selectedIdsProvider
        self.selectedAssetsProvider = selectedAssetsProvider
        self.onToggleSelection = onToggleSelection
        self.onConfirmSelection = onConfirmSelection
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0)

        contentContainer.alpha = 0
        contentContainer.transform = CGAffineTransform(scaleX: 0.93, y: 0.93)
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupCollectionView()
        setupTopChrome()
        setupBottomChrome()
        setupToastOverlay()
        refreshControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Wait until collectionView has a valid non-zero width, force layout so
        // contentSize is ready, then jump directly via contentOffset. This avoids
        // the iOS 14+ UIKit bug where `scrollToItem` fails silently when
        // `isPagingEnabled == true`.
        // 等待 collectionView 获得有效宽度并完成内容尺寸布局后，直接通过 contentOffset
        // 精确定位到目标索引，彻底规避 iOS 14+ 在开启分页时 scrollToItem 静默失效停在第 1 张的问题。
        guard !hasScrolledToInitial, assets.count > 0 else { return }
        contentContainer.layoutIfNeeded()
        guard collectionView.bounds.width > 0 else { return }
        hasScrolledToInitial = true
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        scrollToPage(currentIndex, animated: false)
    }

    private func scrollToPage(_ index: Int, animated: Bool) {
        let pageWidth = collectionView.bounds.width
        guard pageWidth > 0, index >= 0, index < assets.count else { return }
        let targetX = CGFloat(index) * pageWidth
        collectionView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAnimatedEntrance else { return }
        hasAnimatedEntrance = true
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.view.backgroundColor = .black
            self.contentContainer.alpha = 1
            self.contentContainer.transform = .identity
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
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PreviewAssetCell.self, forCellWithReuseIdentifier: PreviewAssetCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func setupTopChrome() {
        topChrome.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(topChrome)

        let backConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        backButton.setImage(UIImage(systemName: "arrow.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        backButton.layer.cornerRadius = 20
        backButton.layer.borderWidth = 1.0 / UIScreen.main.scale
        backButton.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(handleBack), for: .touchUpInside)
        topChrome.addSubview(backButton)

        counterLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        counterLabel.textColor = .white
        counterLabel.textAlignment = .center
        counterLabel.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        counterLabel.layer.cornerRadius = 14
        counterLabel.clipsToBounds = true
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        topChrome.addSubview(counterLabel)

        selectBadgeHitButton.translatesAutoresizingMaskIntoConstraints = false
        selectBadgeHitButton.addTarget(self, action: #selector(handleToggleSelect), for: .touchUpInside)
        topChrome.addSubview(selectBadgeHitButton)

        selectBadgeCircle.layer.cornerRadius = 14
        selectBadgeCircle.clipsToBounds = true
        selectBadgeCircle.isUserInteractionEnabled = false
        selectBadgeCircle.translatesAutoresizingMaskIntoConstraints = false
        selectBadgeHitButton.addSubview(selectBadgeCircle)

        selectBadgeNumber.font = .systemFont(ofSize: 13, weight: .bold)
        selectBadgeNumber.textAlignment = .center
        selectBadgeNumber.translatesAutoresizingMaskIntoConstraints = false
        selectBadgeCircle.addSubview(selectBadgeNumber)

        selectBadgeCheck.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
        selectBadgeCheck.contentMode = .scaleAspectFit
        selectBadgeCheck.isHidden = true
        selectBadgeCheck.translatesAutoresizingMaskIntoConstraints = false
        selectBadgeCircle.addSubview(selectBadgeCheck)

        NSLayoutConstraint.activate([
            topChrome.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            topChrome.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            topChrome.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            backButton.leadingAnchor.constraint(equalTo: topChrome.leadingAnchor, constant: 14),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
            backButton.bottomAnchor.constraint(equalTo: topChrome.bottomAnchor, constant: -18),

            counterLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            counterLabel.centerXAnchor.constraint(equalTo: topChrome.centerXAnchor),
            counterLabel.heightAnchor.constraint(equalToConstant: 28),
            counterLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            selectBadgeHitButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            selectBadgeHitButton.trailingAnchor.constraint(equalTo: topChrome.trailingAnchor, constant: -10),
            selectBadgeHitButton.widthAnchor.constraint(equalToConstant: 44),
            selectBadgeHitButton.heightAnchor.constraint(equalToConstant: 44),

            selectBadgeCircle.centerXAnchor.constraint(equalTo: selectBadgeHitButton.centerXAnchor),
            selectBadgeCircle.centerYAnchor.constraint(equalTo: selectBadgeHitButton.centerYAnchor),
            selectBadgeCircle.widthAnchor.constraint(equalToConstant: 28),
            selectBadgeCircle.heightAnchor.constraint(equalToConstant: 28),

            selectBadgeNumber.centerXAnchor.constraint(equalTo: selectBadgeCircle.centerXAnchor),
            selectBadgeNumber.centerYAnchor.constraint(equalTo: selectBadgeCircle.centerYAnchor),

            selectBadgeCheck.centerXAnchor.constraint(equalTo: selectBadgeCircle.centerXAnchor),
            selectBadgeCheck.centerYAnchor.constraint(equalTo: selectBadgeCircle.centerYAnchor),
            selectBadgeCheck.widthAnchor.constraint(equalToConstant: 15),
            selectBadgeCheck.heightAnchor.constraint(equalToConstant: 15),
        ])
    }

    private func setupBottomChrome() {
        bottomChrome.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(bottomChrome)

        let stripLayout = UICollectionViewFlowLayout()
        stripLayout.scrollDirection = .horizontal
        stripLayout.minimumLineSpacing = 8
        stripLayout.itemSize = CGSize(width: 50, height: 50)
        stripLayout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        stripCollectionView = UICollectionView(frame: .zero, collectionViewLayout: stripLayout)
        stripCollectionView.backgroundColor = .clear
        stripCollectionView.showsHorizontalScrollIndicator = false
        stripCollectionView.dataSource = self
        stripCollectionView.delegate = self
        stripCollectionView.register(SelectedStripCell.self, forCellWithReuseIdentifier: SelectedStripCell.reuseId)
        stripCollectionView.translatesAutoresizingMaskIntoConstraints = false
        bottomChrome.addSubview(stripCollectionView)

        confirmButton.backgroundColor = config.theme.primaryColor
        confirmButton.setTitleColor(config.theme.onPrimaryColor, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        confirmButton.layer.cornerRadius = 21
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(handleConfirm), for: .touchUpInside)
        bottomChrome.addSubview(confirmButton)

        stripHeightConstraint = stripCollectionView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            bottomChrome.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            bottomChrome.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            bottomChrome.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            stripCollectionView.topAnchor.constraint(equalTo: bottomChrome.topAnchor, constant: 12),
            stripCollectionView.leadingAnchor.constraint(equalTo: bottomChrome.leadingAnchor),
            stripCollectionView.trailingAnchor.constraint(equalTo: bottomChrome.trailingAnchor),
            stripHeightConstraint,

            confirmButton.topAnchor.constraint(equalTo: stripCollectionView.bottomAnchor, constant: 8),
            confirmButton.trailingAnchor.constraint(equalTo: bottomChrome.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    private func setupToastOverlay() {
        toastContainer.backgroundColor = UIColor(white: 0.14, alpha: 0.92)
        toastContainer.layer.cornerRadius = 18
        toastContainer.layer.borderWidth = 1.0 / UIScreen.main.scale
        toastContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        toastContainer.alpha = 0
        toastContainer.isHidden = true
        toastContainer.isUserInteractionEnabled = false
        toastContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastContainer)

        toastLabel.font = .systemFont(ofSize: 14, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastContainer.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastContainer.bottomAnchor.constraint(equalTo: bottomChrome.topAnchor, constant: -12),
            toastContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            toastContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            toastLabel.topAnchor.constraint(equalTo: toastContainer.topAnchor, constant: 9),
            toastLabel.bottomAnchor.constraint(equalTo: toastContainer.bottomAnchor, constant: -9),
            toastLabel.leadingAnchor.constraint(equalTo: toastContainer.leadingAnchor, constant: 16),
            toastLabel.trailingAnchor.constraint(equalTo: toastContainer.trailingAnchor, constant: -16),
        ])
    }

    private func showToast(_ message: String) {
        toastHideWorkItem?.cancel()
        toastLabel.text = message
        toastContainer.isHidden = false
        toastContainer.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.toastContainer.alpha = 1
            self.toastContainer.transform = .identity
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.2, animations: {
                self.toastContainer.alpha = 0
            }, completion: { _ in
                self.toastContainer.isHidden = true
            })
        }
        toastHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    private func dismissAnimated(completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        stopActiveVideo()
        UIView.animate(withDuration: 0.19, delay: 0, options: [.curveEaseIn], animations: {
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0)
            self.contentContainer.alpha = 0
            self.contentContainer.transform = CGAffineTransform(scaleX: 0.93, y: 0.93)
        }, completion: { _ in
            self.dismiss(animated: false, completion: completion)
        })
    }

    private func toggleChrome() {
        isChromeVisible.toggle()
        let alpha: CGFloat = isChromeVisible ? 1 : 0
        UIView.animate(withDuration: 0.18) {
            self.topChrome.alpha = alpha
            self.bottomChrome.alpha = alpha
        }
    }

    @objc private func handleBack() {
        dismissAnimated()
    }

    @objc private func handleToggleSelect() {
        guard currentIndex < assets.count else { return }
        let asset = assets.object(at: currentIndex)
        if onToggleSelection(asset) {
            selectBadgeCircle.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            UIView.animate(withDuration: 0.18) {
                self.selectBadgeCircle.transform = .identity
            }
            refreshControls()
        } else if let max = config.maxFiles {
            let msg = config.strings.maxSelectionReached.replacingOccurrences(of: "{max}", with: "\(max)")
            showToast(msg)
        }
    }

    @objc private func handleConfirm() {
        let ids = selectedIdsProvider()
        if !config.multiple, ids.isEmpty, currentIndex < assets.count {
            _ = onToggleSelection(assets.object(at: currentIndex))
        }
        if !selectedIdsProvider().isEmpty {
            dismissAnimated {
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
        counterLabel.text = "  \(currentIndex + 1) / \(assets.count)  "
        let ids = selectedIdsProvider()
        let currentId = currentIndex < assets.count ? assets.object(at: currentIndex).localIdentifier : ""
        let selIdx = ids.firstIndex(of: currentId)
        let limitReached = config.multiple && config.maxFiles != nil && ids.count >= config.maxFiles! && selIdx == nil

        if let idx = selIdx {
            selectBadgeCircle.alpha = 1
            selectBadgeCircle.backgroundColor = config.theme.primaryColor
            selectBadgeCircle.layer.borderWidth = 0
            if config.multiple {
                selectBadgeCheck.isHidden = true
                selectBadgeNumber.isHidden = false
                selectBadgeNumber.text = "\(idx + 1)"
                selectBadgeNumber.textColor = config.theme.onPrimaryColor
            } else {
                selectBadgeNumber.isHidden = true
                selectBadgeCheck.isHidden = false
                selectBadgeCheck.tintColor = config.theme.onPrimaryColor
            }
        } else {
            selectBadgeNumber.isHidden = true
            selectBadgeCheck.isHidden = true
            selectBadgeCircle.alpha = limitReached ? 0.45 : 1.0
            selectBadgeCircle.backgroundColor = config.theme.unselectedBadgeFillColor
            selectBadgeCircle.layer.borderWidth = 2
            selectBadgeCircle.layer.borderColor = config.theme.unselectedBadgeBorderColor.cgColor
        }

        let count = ids.count
        let title = count > 0 ? "\(config.strings.done) (\(count))" : config.strings.done
        confirmButton.setTitle(title, for: .normal)
        confirmButton.alpha = (count > 0 || !config.multiple) ? 1.0 : 0.78

        let showStrip = config.multiple && count > 0
        stripHeightConstraint.constant = showStrip ? 66 : 0
        stripCollectionView.isHidden = !showStrip
        if showStrip {
            if ids != lastRenderedStripIds {
                lastRenderedStripIds = ids
                UIView.performWithoutAnimation {
                    self.stripCollectionView.reloadData()
                }
            } else {
                // Only update border highlights in place when swiping pages (zero flash).
                // 滑动切换页面时仅就地更新高亮边框，不触发 reloadData，彻底避免底部缩略图闪烁。
                updateVisibleStripHighlights(currentId: currentId)
            }
        } else if !lastRenderedStripIds.isEmpty {
            lastRenderedStripIds = []
        }
    }

    private func updateVisibleStripHighlights(currentId: String) {
        for cell in stripCollectionView.visibleCells {
            guard let stripCell = cell as? SelectedStripCell else { continue }
            stripCell.updateHighlight(
                isCurrent: stripCell.assetId == currentId,
                accentColor: config.theme.primaryColor
            )
        }
    }

    // MARK: - UICollectionViewDataSource & Delegate

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === stripCollectionView {
            return selectedAssetsProvider().count
        }
        return assets.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if collectionView === stripCollectionView {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SelectedStripCell.reuseId,
                for: indexPath
            ) as? SelectedStripCell else {
                return UICollectionViewCell()
            }
            let selectedAssets = selectedAssetsProvider()
            guard indexPath.item < selectedAssets.count else { return cell }
            let asset = selectedAssets[indexPath.item]
            let isCurrent = currentIndex < assets.count
                && assets.object(at: currentIndex).localIdentifier == asset.localIdentifier
            cell.configure(
                asset: asset,
                repository: repository,
                isCurrent: isCurrent,
                accentColor: config.theme.primaryColor
            )
            return cell
        }

        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PreviewAssetCell.reuseId,
            for: indexPath
        ) as? PreviewAssetCell else {
            return UICollectionViewCell()
        }
        let asset = assets.object(at: indexPath.item)
        cell.configure(
            asset: asset,
            repository: repository,
            onSingleTap: { [weak self] in self?.toggleChrome() },
            onPlay: { [weak self, weak cell] in
                guard let self = self, let cell = cell else { return }
                self.playVideo(asset: asset, in: cell)
            }
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView === stripCollectionView else { return }
        let selectedAssets = selectedAssetsProvider()
        guard indexPath.item < selectedAssets.count else { return }
        let targetId = selectedAssets[indexPath.item].localIdentifier
        for i in 0..<assets.count {
            if assets.object(at: i).localIdentifier == targetId {
                if i != currentIndex {
                    stopActiveVideo()
                    currentIndex = i
                    self.scrollToPage(i, animated: true)
                    refreshControls()
                }
                break
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if collectionView === stripCollectionView {
            return CGSize(width: 50, height: 50)
        }
        return collectionView.bounds.size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === collectionView { updateCurrentIndexFromScroll() }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === collectionView, !decelerate { updateCurrentIndexFromScroll() }
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

/// Horizontal thumbnail cell in the bottom selected-items strip.
/// 底部已选缩略图快速跳转条单元格。
private final class SelectedStripCell: UICollectionViewCell {
    static let reuseId = "XueHuaSelectedStripCell"

    private let imageView = UIImageView()
    private(set) var assetId = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 9
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 7
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateHighlight(isCurrent: Bool, accentColor: UIColor) {
        contentView.layer.borderWidth = isCurrent ? 2.2 : 0
        contentView.layer.borderColor = isCurrent ? accentColor.cgColor : UIColor.clear.cgColor
    }

    func configure(
        asset: PHAsset,
        repository: PhotoLibraryRepository,
        isCurrent: Bool,
        accentColor: UIColor
    ) {
        updateHighlight(isCurrent: isCurrent, accentColor: accentColor)
        guard assetId != asset.localIdentifier else { return }
        assetId = asset.localIdentifier
        imageView.image = nil
        repository.requestThumbnail(for: asset, targetSize: CGSize(width: 120, height: 120)) { [weak self] img in
            DispatchQueue.main.async {
                if self?.assetId == asset.localIdentifier, let img = img {
                    self?.imageView.image = img
                }
            }
        }
    }
}

/// Zoomable full-screen preview cell supporting pinch zoom, double-tap zoom,
/// single-tap chrome toggle, and inline video playback trigger.
/// 支持双指缩放、双击放大/还原、轻触切栏与视频播放的全屏预览单元格。
private final class PreviewAssetCell: UICollectionViewCell, UIScrollViewDelegate {
    static let reuseId = "XueHuaPreviewAssetCell"

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let playButton = UIButton(type: .system)
    private var requestId: PHImageRequestID = PHInvalidImageRequestID
    private var assetId: String = ""
    private var onSingleTap: (() -> Void)?
    private var onPlay: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: iconConfig), for: .normal)
        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        playButton.layer.cornerRadius = 33
        playButton.layer.borderWidth = 1.5
        playButton.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(handlePlay), for: .touchUpInside)
        contentView.addSubview(playButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            playButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 66),
            playButton.heightAnchor.constraint(equalToConstant: 66),
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
        assetId = ""
        scrollView.setZoomScale(1.0, animated: false)
        imageView.image = nil
        playButton.isHidden = true
        onSingleTap = nil
        onPlay = nil
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func configure(
        asset: PHAsset,
        repository: PhotoLibraryRepository,
        onSingleTap: @escaping () -> Void,
        onPlay: @escaping () -> Void
    ) {
        if requestId != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestId)
            requestId = PHInvalidImageRequestID
        }
        let targetAssetId = asset.localIdentifier
        self.assetId = targetAssetId
        self.onSingleTap = onSingleTap
        self.onPlay = onPlay
        scrollView.setZoomScale(1.0, animated: false)
        imageView.image = nil
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
                // Guard against stale async callbacks after cell reuse.
                // 校验资产 ID，防止单元格复用后旧异步回调覆盖当前预览图。
                if self?.assetId == targetAssetId, let image = image {
                    self?.imageView.image = image
                }
            }
        }
    }

    func setPlayButtonHidden(_ hidden: Bool) {
        playButton.isHidden = hidden
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.05 {
            scrollView.setZoomScale(1.0, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let zoomRectSize = CGSize(
                width: scrollView.bounds.width / 2.4,
                height: scrollView.bounds.height / 2.4
            )
            let zoomRect = CGRect(
                x: point.x - zoomRectSize.width / 2,
                y: point.y - zoomRectSize.height / 2,
                width: zoomRectSize.width,
                height: zoomRectSize.height
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func handlePlay() {
        onPlay?()
    }
}
