import Photos
import PhotosUI
import UIKit

/// Customizable native sheet-style media picker for iOS (iOS 14.0+).
/// Uses a unified simultaneous nested-scroll pan gesture so dragging anywhere
/// on the sheet or grid tracks the finger 1:1 between half-screen, full-screen,
/// and dismiss states with spring physics and zero layout jumps.
///
/// iOS 端可自定义样式的原生抽屉式媒体选择器（兼容 iOS 14.0+）。
/// 采用统一的嵌套手势协同机制：支持在面板或网格任意位置跟手 1:1 上拉展开至全屏、
/// 全屏滑到顶部后无缝下拉回半屏或继续下拉关闭，结合弹簧阻尼物理吸附且全程零跳变。
final class CustomMediaPickerViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UIGestureRecognizerDelegate,
    PHPhotoLibraryChangeObserver
{
    private let config: CustomMediaPickerConfig
    private var authStatus: PHAuthorizationStatus
    private let onComplete: ([PHAsset]?) -> Void
    private let onOpenInOtherApp: () -> Void
    private let onLaunchCamera: () -> Void

    private let repository = PhotoLibraryRepository()
    private var albums: [MediaAlbumItem] = []
    private var currentAlbumIndex: Int = 0
    private var selectedAssetIds: [String] = []
    private var selectedAssetsById: [String: PHAsset] = [:]

    private var hasAnimatedEntrance = false
    private var isDismissing = false
    private var deliveredResult = false
    private var screenHeight: CGFloat = 0
    private var collapsedTopOffset: CGFloat = 0
    private var currentSheetOffsetY: CGFloat = 0

    // Nested-scroll pan state / 嵌套手势拖拽状态
    private var panStartOffsetY: CGFloat = 0
    private var panStartedInFullscreen = false
    private var isDraggingSheet = false
    private var sheetPanGesture: UIPanGestureRecognizer!

    private let scrimView = UIView()
    private let sheetContainer = UIView()
    private let dragHandlePill = UIView()
    private let limitedBanner = UIView()
    private var collectionView: UICollectionView!

    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let albumPillButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)

    private let fastScrollThumb = UIButton(type: .system)
    private var fastScrollTopConstraint: NSLayoutConstraint!
    private let dateBubbleLabel = UILabel()
    private var dateBubbleHideWorkItem: DispatchWorkItem?

    private let bottomBar = UIView()
    private let confirmButton = UIButton(type: .system)

    private let emptyStateStack = UIStackView()
    private let emptyMessageLabel = UILabel()
    private let settingsButton = UIButton(type: .system)

    private var popoverBackdrop: UIView?

    init(
        config: CustomMediaPickerConfig,
        authStatus: PHAuthorizationStatus,
        onComplete: @escaping ([PHAsset]?) -> Void,
        onOpenInOtherApp: @escaping () -> Void,
        onLaunchCamera: @escaping () -> Void
    ) {
        self.config = config
        self.authStatus = authStatus
        self.onComplete = onComplete
        self.onOpenInOtherApp = onOpenInOtherApp
        self.onLaunchCamera = onLaunchCamera
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        screenHeight = UIScreen.main.bounds.height
        collapsedTopOffset = screenHeight * 0.42

        setupScrimAndSheet()
        setupCollectionView()
        setupDragHandle()
        setupLimitedBannerIfNeeded()
        setupFloatingTopBar()
        setupFastScroller()
        setupBottomBar()
        setupEmptyOrDeniedState()
        setupUnifiedSheetPanGesture()

        // Start off-screen for smooth spring entrance / 初始置于屏幕底部以便弹簧滑入
        applySheetOffset(screenHeight)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        if authStatus == .authorized || authStatus == .limited {
            PHPhotoLibrary.shared().register(self)
            loadAlbumsAsync()
        } else {
            showDeniedState()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAnimatedEntrance else { return }
        hasAnimatedEntrance = true
        let targetOffset: CGFloat = config.initialExpanded ? 0 : collapsedTopOffset
        animateSheet(toOffset: targetOffset, duration: 0.34, damping: 0.88)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopVisibleCameraCells()
    }

    @objc private func handleAppDidBecomeActive() {
        let latest = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if (authStatus != .authorized && authStatus != .limited) && (latest == .authorized || latest == .limited) {
            authStatus = latest
            PHPhotoLibrary.shared().register(self)
            emptyStateStack.isHidden = true
            collectionView.isHidden = false
            applySheetOffset(currentSheetOffsetY)
            loadAlbumsAsync()
        }
    }

    // MARK: - Layout Setup / 界面布局构建

    private func setupScrimAndSheet() {
        scrimView.backgroundColor = config.theme.scrimColor
        scrimView.alpha = 0
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCancel))
        scrimView.addGestureRecognizer(tap)
        view.addSubview(scrimView)

        // Sheet always spans full viewport height; position is driven purely by transform.
        // 抽屉始终保持全屏高度，通过 GPU transform 驱动垂直位置，彻底消除 Auto Layout 冲突与抖动。
        sheetContainer.backgroundColor = config.theme.backgroundColor
        sheetContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetContainer.layer.cornerRadius = config.theme.sheetCornerRadius
        sheetContainer.clipsToBounds = true
        sheetContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheetContainer)

        NSLayoutConstraint.activate([
            scrimView.topAnchor.constraint(equalTo: view.topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sheetContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCompositionalLayout())
        collectionView.backgroundColor = config.theme.backgroundColor
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = UIEdgeInsets(top: 24, left: 0, bottom: 96, right: 0)
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MediaThumbnailCell.self, forCellWithReuseIdentifier: MediaThumbnailCell.reuseId)
        collectionView.register(CameraPreviewCell.self, forCellWithReuseIdentifier: CameraPreviewCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: sheetContainer.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor),
        ])
    }

    private func setupDragHandle() {
        dragHandlePill.backgroundColor = config.theme.handleColor
        dragHandlePill.layer.cornerRadius = 2.5
        dragHandlePill.isUserInteractionEnabled = false
        dragHandlePill.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(dragHandlePill)

        NSLayoutConstraint.activate([
            dragHandlePill.topAnchor.constraint(equalTo: sheetContainer.topAnchor, constant: 10),
            dragHandlePill.centerXAnchor.constraint(equalTo: sheetContainer.centerXAnchor),
            dragHandlePill.widthAnchor.constraint(equalToConstant: 40),
            dragHandlePill.heightAnchor.constraint(equalToConstant: 5),
        ])
    }

    private func setupLimitedBannerIfNeeded() {
        guard authStatus == .limited else { return }
        limitedBanner.backgroundColor = config.theme.surfaceColor
        limitedBanner.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(limitedBanner)

        let hint = UILabel()
        hint.text = config.strings.limitedAccessHint
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = config.theme.secondaryTextColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        limitedBanner.addSubview(hint)

        let manageBtn = UIButton(type: .system)
        manageBtn.setTitle(config.strings.managePermission, for: .normal)
        manageBtn.setTitleColor(config.theme.primaryColor, for: .normal)
        manageBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        manageBtn.translatesAutoresizingMaskIntoConstraints = false
        manageBtn.addTarget(self, action: #selector(handleManageLimitedAccess), for: .touchUpInside)
        limitedBanner.addSubview(manageBtn)

        collectionView.contentInset = UIEdgeInsets(top: 64, left: 0, bottom: 96, right: 0)

        NSLayoutConstraint.activate([
            limitedBanner.topAnchor.constraint(equalTo: sheetContainer.safeAreaLayoutGuide.topAnchor, constant: 56),
            limitedBanner.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            limitedBanner.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            limitedBanner.heightAnchor.constraint(equalToConstant: 40),

            hint.leadingAnchor.constraint(equalTo: limitedBanner.leadingAnchor, constant: 16),
            hint.centerYAnchor.constraint(equalTo: limitedBanner.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: manageBtn.leadingAnchor, constant: -12),

            manageBtn.trailingAnchor.constraint(equalTo: limitedBanner.trailingAnchor, constant: -16),
            manageBtn.centerYAnchor.constraint(equalTo: limitedBanner.centerYAnchor),
        ])
    }

    private func setupUnifiedSheetPanGesture() {
        sheetPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleUnifiedPan(_:)))
        sheetPanGesture.delegate = self
        sheetPanGesture.cancelsTouchesInView = false
        sheetContainer.addGestureRecognizer(sheetPanGesture)
    }

    /// Builds a compositional layout whose Section 0 renders the optional 1x2
    /// camera tile on the left paired with 2 rows of media cells on the right,
    /// and Section 1 renders a uniform N-column media grid.
    /// 构建组合式布局：第 0 组渲染可选的左侧 1×2 实时相机格 + 右侧 2 行缩略图，
    /// 第 1 组渲染标准多列媒体网格。
    private func makeCompositionalLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            guard let self = self else { return nil }
            let cols = CGFloat(self.config.crossAxisCount)
            let spacing = self.config.theme.gridSpacing

            if sectionIndex == 0, self.hasHeroCameraSection() {
                let leftFrac = 1.0 / cols
                let rightFrac = 1.0 - leftFrac
                let rightCols = max(1, self.config.crossAxisCount - 1)

                let cameraItem = NSCollectionLayoutItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(leftFrac),
                        heightDimension: .fractionalHeight(1.0)
                    )
                )
                cameraItem.contentInsets = NSDirectionalEdgeInsets(
                    top: 0, leading: 0, bottom: spacing, trailing: spacing
                )

                let miniItem = NSCollectionLayoutItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0 / CGFloat(rightCols)),
                        heightDimension: .fractionalHeight(1.0)
                    )
                )
                miniItem.contentInsets = NSDirectionalEdgeInsets(
                    top: 0, leading: 0, bottom: spacing, trailing: spacing
                )

                let miniRow = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0),
                        heightDimension: .fractionalHeight(0.5)
                    ),
                    subitem: miniItem,
                    count: rightCols
                )

                let rightStack = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(rightFrac),
                        heightDimension: .fractionalHeight(1.0)
                    ),
                    subitem: miniRow,
                    count: 2
                )

                let heroHeightFrac = 2.0 / cols
                let heroGroup = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0),
                        heightDimension: .fractionalWidth(heroHeightFrac)
                    ),
                    subitems: [cameraItem, rightStack]
                )
                return NSCollectionLayoutSection(group: heroGroup)
            }

            let cellItem = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0 / cols),
                    heightDimension: .fractionalHeight(1.0)
                )
            )
            cellItem.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: 0, bottom: spacing, trailing: spacing
            )
            let rowGroup = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalWidth(1.0 / cols)
                ),
                subitem: cellItem,
                count: self.config.crossAxisCount
            )
            return NSCollectionLayoutSection(group: rowGroup)
        }
    }

    private func setupFloatingTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(topBar)

        let backIcon = UIImage(
            systemName: "arrow.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        styleFloatingPill(backButton, cornerRadius: 21)
        backButton.setImage(backIcon, for: .normal)
        backButton.tintColor = config.theme.iconColor
        backButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
        topBar.addSubview(backButton)

        let chevronIcon = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        )
        styleFloatingPill(albumPillButton, cornerRadius: 21)
        albumPillButton.setTitle(config.strings.galleryTitle, for: .normal)
        albumPillButton.setImage(chevronIcon, for: .normal)
        albumPillButton.tintColor = config.theme.iconColor
        albumPillButton.setTitleColor(config.theme.textColor, for: .normal)
        albumPillButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        albumPillButton.semanticContentAttribute = .forceRightToLeft
        albumPillButton.imageEdgeInsets = UIEdgeInsets(top: 1, left: 6, bottom: 0, right: -6)
        albumPillButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 20)
        albumPillButton.addTarget(self, action: #selector(handleAlbumPillTap), for: .touchUpInside)
        topBar.addSubview(albumPillButton)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: sheetContainer.safeAreaLayoutGuide.topAnchor, constant: 6),
            topBar.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor, constant: 14),
            topBar.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor, constant: -14),
            topBar.heightAnchor.constraint(equalToConstant: 46),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42),

            albumPillButton.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            albumPillButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            albumPillButton.heightAnchor.constraint(equalToConstant: 42),
            albumPillButton.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 10),
        ])

        if config.allowOpenInOtherApp {
            let moreIcon = UIImage(
                systemName: "ellipsis",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            )
            styleFloatingPill(moreButton, cornerRadius: 21)
            moreButton.setImage(moreIcon, for: .normal)
            moreButton.tintColor = config.theme.iconColor
            moreButton.addTarget(self, action: #selector(handleMoreTap), for: .touchUpInside)
            topBar.addSubview(moreButton)

            NSLayoutConstraint.activate([
                moreButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
                moreButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
                moreButton.widthAnchor.constraint(equalToConstant: 42),
                moreButton.heightAnchor.constraint(equalToConstant: 42),
                albumPillButton.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -10),
            ])
        }
    }

    private func styleFloatingPill(_ button: UIButton, cornerRadius: CGFloat) {
        button.backgroundColor = config.theme.surfaceColor
        button.layer.cornerRadius = cornerRadius
        button.layer.borderWidth = 1.0 / UIScreen.main.scale
        button.layer.borderColor = (config.theme.isDark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.08)).cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.12
        button.layer.shadowRadius = 6
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupFastScroller() {
        let icon = UIImage(
            systemName: "chevron.up.chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        )
        styleFloatingPill(fastScrollThumb, cornerRadius: 19)
        fastScrollThumb.setImage(icon, for: .normal)
        fastScrollThumb.tintColor = config.theme.iconColor
        fastScrollThumb.isHidden = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleFastScrollPan(_:)))
        fastScrollThumb.addGestureRecognizer(pan)
        sheetContainer.addSubview(fastScrollThumb)

        dateBubbleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        dateBubbleLabel.textColor = config.theme.dateBubbleTextColor
        dateBubbleLabel.backgroundColor = config.theme.dateBubbleBackgroundColor
        dateBubbleLabel.layer.cornerRadius = 16
        dateBubbleLabel.clipsToBounds = true
        dateBubbleLabel.textAlignment = .center
        dateBubbleLabel.alpha = 0
        dateBubbleLabel.isHidden = true
        dateBubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(dateBubbleLabel)

        fastScrollTopConstraint = fastScrollThumb.topAnchor.constraint(
            equalTo: sheetContainer.safeAreaLayoutGuide.topAnchor,
            constant: 64
        )

        NSLayoutConstraint.activate([
            fastScrollTopConstraint,
            fastScrollThumb.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor, constant: -6),
            fastScrollThumb.widthAnchor.constraint(equalToConstant: 38),
            fastScrollThumb.heightAnchor.constraint(equalToConstant: 38),

            dateBubbleLabel.centerYAnchor.constraint(equalTo: fastScrollThumb.centerYAnchor),
            dateBubbleLabel.trailingAnchor.constraint(equalTo: fastScrollThumb.leadingAnchor, constant: -10),
            dateBubbleLabel.heightAnchor.constraint(equalToConstant: 32),
            dateBubbleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 108),
        ])
    }

    private func setupBottomBar() {
        // Mount on self.view (not sheetContainer) so the Done button stays visible
        // in BOTH half-screen and full-screen modes, showing only the right-aligned button.
        // 挂载在根视图 self.view 上，确保半屏与全屏模式下底部完成按钮均始终可见，且仅显示右侧完成按钮。
        bottomBar.backgroundColor = config.theme.surfaceColor
        bottomBar.layer.shadowColor = UIColor.black.cgColor
        bottomBar.layer.shadowOpacity = 0.1
        bottomBar.layer.shadowRadius = 8
        bottomBar.layer.shadowOffset = CGSize(width: 0, height: -2)
        bottomBar.isHidden = true
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        confirmButton.backgroundColor = config.theme.primaryColor
        confirmButton.setTitleColor(config.theme.onPrimaryColor, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        confirmButton.layer.cornerRadius = 20
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(handleConfirmSelection), for: .touchUpInside)
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

    private func setupEmptyOrDeniedState() {
        emptyStateStack.axis = .vertical
        emptyStateStack.alignment = .center
        emptyStateStack.spacing = 16
        emptyStateStack.isHidden = true
        emptyStateStack.translatesAutoresizingMaskIntoConstraints = false

        emptyMessageLabel.font = .systemFont(ofSize: 15)
        emptyMessageLabel.textColor = config.theme.secondaryTextColor
        emptyMessageLabel.textAlignment = .center
        emptyMessageLabel.numberOfLines = 0
        emptyStateStack.addArrangedSubview(emptyMessageLabel)

        settingsButton.setTitle(config.strings.openSettings, for: .normal)
        settingsButton.setTitleColor(config.theme.onPrimaryColor, for: .normal)
        settingsButton.backgroundColor = config.theme.primaryColor
        settingsButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        settingsButton.layer.cornerRadius = 20
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
        settingsButton.addTarget(self, action: #selector(handleOpenSettings), for: .touchUpInside)
        emptyStateStack.addArrangedSubview(settingsButton)

        sheetContainer.addSubview(emptyStateStack)
        NSLayoutConstraint.activate([
            emptyStateStack.centerXAnchor.constraint(equalTo: sheetContainer.centerXAnchor),
            emptyStateStack.centerYAnchor.constraint(equalTo: sheetContainer.centerYAnchor),
            emptyStateStack.leadingAnchor.constraint(greaterThanOrEqualTo: sheetContainer.leadingAnchor, constant: 32),
            emptyStateStack.trailingAnchor.constraint(lessThanOrEqualTo: sheetContainer.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Sheet Physics & Nested Scroll Coordination / 抽屉物理动画与嵌套手势协调

    /// Applies pure GPU visual state for any vertical sheet offset without
    /// mutating Auto Layout constraints or collectionView insets.
    /// 根据抽屉垂直偏移量实时更新纯 GPU 视觉属性（圆角、遮罩、拖拽条、悬浮顶栏），
    /// 全程不改约束与列表内边距，彻底杜绝跳变与卡顿。
    private func applySheetOffset(_ offsetY: CGFloat) {
        let clamped = min(max(offsetY, 0), screenHeight)
        currentSheetOffsetY = clamped
        sheetContainer.transform = CGAffineTransform(translationX: 0, y: clamped)

        let half = max(collapsedTopOffset, 1)
        let expandProgress = min(max(1.0 - (clamped / half), 0), 1)

        let scrimAlpha: CGFloat
        if clamped <= half {
            scrimAlpha = 1.0
        } else {
            let dismissRange = max(screenHeight - half, 1)
            scrimAlpha = min(max(1.0 - ((clamped - half) / dismissRange), 0), 1)
        }
        scrimView.alpha = scrimAlpha
        if !bottomBar.isHidden && !selectedAssetIds.isEmpty {
            bottomBar.alpha = scrimAlpha
        }

        sheetContainer.layer.cornerRadius = config.theme.sheetCornerRadius * (1.0 - expandProgress)
        dragHandlePill.alpha = min(max(1.0 - expandProgress * 1.8, 0), 1)

        let isDenied = authStatus != .authorized && authStatus != .limited
        let topBarAlpha: CGFloat = isDenied ? 1.0 : min(max((expandProgress - 0.35) / 0.65, 0), 1)
        topBar.alpha = topBarAlpha
        topBar.isUserInteractionEnabled = topBarAlpha > 0.1
        topBar.transform = CGAffineTransform(translationX: 0, y: -(1.0 - topBarAlpha) * 14)
    }

    private func animateSheet(
        toOffset targetOffset: CGFloat,
        duration: TimeInterval = 0.30,
        damping: CGFloat = 0.90,
        completion: (() -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: damping,
            initialSpringVelocity: 0.3,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.applySheetOffset(targetOffset)
            },
            completion: { _ in
                completion?()
            }
        )
    }

    private func dismissAnimated(completion: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true
        dismissPopover()
        stopVisibleCameraCells()
        UIView.animate(withDuration: 0.23, delay: 0, options: [.curveEaseIn], animations: {
            self.applySheetOffset(self.screenHeight)
        }, completion: { _ in
            self.dismiss(animated: false, completion: completion)
        })
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === sheetPanGesture && otherGestureRecognizer === collectionView.panGestureRecognizer {
            return true
        }
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === sheetPanGesture else { return true }
        let loc = gestureRecognizer.location(in: sheetContainer)
        if !fastScrollThumb.isHidden && fastScrollThumb.frame.insetBy(dx: -8, dy: -8).contains(loc) {
            return false
        }
        if !bottomBar.isHidden && bottomBar.frame.contains(loc) {
            return false
        }
        let velocity = sheetPanGesture.velocity(in: sheetContainer)
        return abs(velocity.y) >= abs(velocity.x)
    }

    @objc private func handleUnifiedPan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else { return }
        let translation = gesture.translation(in: view)
        let velocityY = gesture.velocity(in: view).y
        let topRestOffset = -collectionView.contentInset.top
        let isGridAtTop = collectionView.contentOffset.y <= topRestOffset + 1.5

        switch gesture.state {
        case .began:
            panStartOffsetY = currentSheetOffsetY
            panStartedInFullscreen = currentSheetOffsetY <= 2.0
            isDraggingSheet = false

        case .changed:
            let shouldDragSheet: Bool
            if isDraggingSheet {
                shouldDragSheet = true
            } else if currentSheetOffsetY > 2.0 {
                // Half-screen: any vertical swipe moves the sheet 1:1 with finger.
                // 半屏状态：任意上下滑动均 1:1 跟手移动抽屉。
                shouldDragSheet = true
            } else if isGridAtTop && translation.y > 2.0 {
                // Full-screen at top of grid: downward swipe smoothly pulls back to half-screen.
                // 全屏且网格已滑到顶部：向下拉动无缝过渡为下拉抽屉回半屏。
                shouldDragSheet = true
            } else {
                shouldDragSheet = false
            }

            if shouldDragSheet {
                if !isDraggingSheet {
                    isDraggingSheet = true
                    dismissPopover()
                    panStartOffsetY = currentSheetOffsetY
                    gesture.setTranslation(.zero, in: view)
                    return
                }
                // Lock grid at top while sheet tracks the finger so content never jumps.
                // 抽屉跟手期间锁定网格在顶部，避免列表同时滚动造成跳动。
                if collectionView.contentOffset.y != topRestOffset {
                    collectionView.contentOffset = CGPoint(x: 0, y: topRestOffset)
                }
                let nextOffset = max(0, panStartOffsetY + translation.y)
                applySheetOffset(nextOffset)
            }

        case .ended, .cancelled:
            guard isDraggingSheet else { return }
            isDraggingSheet = false
            let offset = currentSheetOffsetY
            let half = collapsedTopOffset

            if velocityY < -550 {
                animateSheet(toOffset: 0)
            } else if velocityY > 1800 {
                handleCancel()
            } else if velocityY > 550 {
                if panStartedInFullscreen && offset < half * 1.15 {
                    animateSheet(toOffset: half)
                } else {
                    handleCancel()
                }
            } else if offset < half * 0.5 {
                animateSheet(toOffset: 0)
            } else if offset <= half + screenHeight * 0.17 {
                animateSheet(toOffset: half)
            } else {
                handleCancel()
            }

        default:
            break
        }
    }

    // MARK: - Data Loading & PhotoLibrary Observation / 数据加载与监听

    private func loadAlbumsAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let loaded = self.repository.loadAlbums(
                mediaType: self.config.mediaType,
                strings: self.config.strings
            )
            DispatchQueue.main.async {
                self.albums = loaded
                if self.currentAlbumIndex >= loaded.count {
                    self.currentAlbumIndex = 0
                }
                self.applyCurrentAlbum()
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        loadAlbumsAsync()
    }

    private var currentAlbum: MediaAlbumItem? {
        guard currentAlbumIndex >= 0, currentAlbumIndex < albums.count else { return nil }
        return albums[currentAlbumIndex]
    }

    private func applyCurrentAlbum() {
        guard let album = currentAlbum else {
            showEmptyState()
            return
        }
        let title = album.isAllMedia ? config.strings.galleryTitle : album.title
        albumPillButton.setTitle(title, for: .normal)
        if album.count == 0 && !hasHeroCameraSection() {
            showEmptyState()
        } else {
            emptyStateStack.isHidden = true
            collectionView.isHidden = false
            collectionView.reloadData()
        }
    }

    private func showDeniedState() {
        collectionView.isHidden = true
        emptyMessageLabel.text = config.strings.permissionDeniedMessage
        settingsButton.isHidden = false
        emptyStateStack.isHidden = false
    }

    private func showEmptyState() {
        collectionView.isHidden = true
        emptyMessageLabel.text = config.strings.emptyAlbum
        settingsButton.isHidden = true
        emptyStateStack.isHidden = false
    }

    private func hasHeroCameraSection() -> Bool {
        guard config.showCameraTile, let album = currentAlbum else { return false }
        return album.isAllMedia
    }

    private func heroRightCapacity() -> Int {
        hasHeroCameraSection() ? 2 * max(1, config.crossAxisCount - 1) : 0
    }

    private func assetIndex(for indexPath: IndexPath) -> Int? {
        guard let album = currentAlbum else { return nil }
        if hasHeroCameraSection() {
            if indexPath.section == 0 {
                if indexPath.item == 0 { return nil }
                let idx = indexPath.item - 1
                return idx < album.count ? idx : nil
            } else {
                let idx = heroRightCapacity() + indexPath.item
                return idx < album.count ? idx : nil
            }
        }
        return indexPath.item < album.count ? indexPath.item : nil
    }

    // MARK: - Actions & Popovers / 交互按钮与浮窗菜单

    @objc private func handleCancel() {
        guard !deliveredResult else { return }
        deliveredResult = true
        dismissAnimated {
            self.onComplete(nil)
        }
    }

    @objc private func handleManageLimitedAccess() {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
    }

    @objc private func handleOpenSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func handleFastScrollPan(_ gesture: UIPanGestureRecognizer) {
        let trackTop: CGFloat = 64
        let trackBottom = max(trackTop + 1, sheetContainer.bounds.height - 160)
        let locationY = gesture.location(in: sheetContainer).y - sheetContainer.safeAreaInsets.top
        let clampedY = min(max(locationY, trackTop), trackBottom)
        let fraction = (clampedY - trackTop) / (trackBottom - trackTop)

        switch gesture.state {
        case .began, .changed:
            fastScrollTopConstraint.constant = clampedY
            let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
            collectionView.contentOffset = CGPoint(x: 0, y: fraction * maxOffset - collectionView.contentInset.top)
            updateDateBubble(show: true)
        case .ended, .cancelled:
            scheduleHideDateBubble()
        default:
            break
        }
    }

    @objc private func handleAlbumPillTap() {
        guard !albums.isEmpty else { return }
        dismissPopover()

        let backdrop = UIView(frame: view.bounds)
        backdrop.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissPopover))
        backdrop.addGestureRecognizer(tap)
        view.addSubview(backdrop)
        popoverBackdrop = backdrop

        let card = UIView()
        card.backgroundColor = config.theme.surfaceColor
        card.layer.cornerRadius = 18
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.2
        card.layer.shadowRadius = 14
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        card.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(card)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        for (index, album) in albums.enumerated() {
            let row = UIButton(type: .system)
            row.tag = index
            row.addTarget(self, action: #selector(handleAlbumSelected(_:)), for: .touchUpInside)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 54).isActive = true

            let thumb = UIImageView()
            thumb.contentMode = .scaleAspectFill
            thumb.clipsToBounds = true
            thumb.layer.cornerRadius = 8
            thumb.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
            thumb.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(thumb)

            if let cover = album.coverAsset {
                repository.requestThumbnail(for: cover, targetSize: CGSize(width: 90, height: 90)) { img in
                    DispatchQueue.main.async { thumb.image = img }
                }
            }

            let nameLabel = UILabel()
            nameLabel.text = album.title
            nameLabel.font = .systemFont(ofSize: 15, weight: index == currentAlbumIndex ? .bold : .regular)
            nameLabel.textColor = config.theme.textColor
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(nameLabel)

            let countLabel = UILabel()
            countLabel.text = "\(album.count)"
            countLabel.font = .systemFont(ofSize: 14)
            countLabel.textColor = config.theme.secondaryTextColor
            countLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(countLabel)

            NSLayoutConstraint.activate([
                thumb.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
                thumb.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                thumb.widthAnchor.constraint(equalToConstant: 40),
                thumb.heightAnchor.constraint(equalToConstant: 40),

                nameLabel.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
                nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

                countLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
                countLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                countLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -14),
            ])
            stack.addArrangedSubview(row)
        }

        let cardHeight = min(CGFloat(albums.count) * 56 + 16, view.bounds.height * 0.55)
        let pillFrame = albumPillButton.convert(albumPillButton.bounds, to: view)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.topAnchor, constant: pillFrame.maxY + 8),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.68),
            card.heightAnchor.constraint(equalToConstant: cardHeight),

            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
            card.alpha = 1
            card.transform = .identity
        }
    }

    @objc private func handleAlbumSelected(_ sender: UIButton) {
        currentAlbumIndex = sender.tag
        dismissPopover()
        applyCurrentAlbum()
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.contentInset.top), animated: false)
    }

    @objc private func handleMoreTap() {
        dismissPopover()

        let backdrop = UIView(frame: view.bounds)
        backdrop.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissPopover))
        backdrop.addGestureRecognizer(tap)
        view.addSubview(backdrop)
        popoverBackdrop = backdrop

        let card = UIView()
        card.backgroundColor = config.theme.surfaceColor
        card.layer.cornerRadius = 16
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.2
        card.layer.shadowRadius = 14
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        card.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(card)

        let openBtn = UIButton(type: .system)
        let icon = UIImage(
            systemName: "arrow.up.forward.square",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        )
        openBtn.setImage(icon, for: .normal)
        openBtn.setTitle("  \(config.strings.openInOtherApp)", for: .normal)
        openBtn.tintColor = config.theme.iconColor
        openBtn.setTitleColor(config.theme.textColor, for: .normal)
        openBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        openBtn.contentHorizontalAlignment = .leading
        openBtn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        openBtn.translatesAutoresizingMaskIntoConstraints = false
        openBtn.addTarget(self, action: #selector(handleOpenInOtherAppTap), for: .touchUpInside)
        card.addSubview(openBtn)

        let moreFrame = moreButton.convert(moreButton.bounds, to: view)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.topAnchor, constant: moreFrame.maxY + 8),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),

            openBtn.topAnchor.constraint(equalTo: card.topAnchor),
            openBtn.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            openBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            openBtn.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
            card.alpha = 1
            card.transform = .identity
        }
    }

    @objc private func handleOpenInOtherAppTap() {
        dismissPopover()
        deliveredResult = true
        dismissAnimated {
            self.onOpenInOtherApp()
        }
    }

    @objc private func dismissPopover() {
        popoverBackdrop?.removeFromSuperview()
        popoverBackdrop = nil
    }

    @objc private func handleConfirmSelection() {
        let assets = selectedAssetIds.compactMap { selectedAssetsById[$0] }
        guard !assets.isEmpty else { return }
        deliveredResult = true
        dismissAnimated {
            self.onComplete(assets)
        }
    }

    private func toggleSelection(for asset: PHAsset) -> Bool {
        let id = asset.localIdentifier
        if let idx = selectedAssetIds.firstIndex(of: id) {
            selectedAssetIds.remove(at: idx)
            selectedAssetsById.removeValue(forKey: id)
            refreshSelectionUI()
            return true
        }
        if !config.multiple {
            selectedAssetIds = [id]
            selectedAssetsById = [id: asset]
            refreshSelectionUI()
            return true
        }
        if let max = config.maxFiles, selectedAssetIds.count >= max {
            let msg = config.strings.maxSelectionReached.replacingOccurrences(of: "{max}", with: "\(max)")
            let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
            present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                alert.dismiss(animated: true)
            }
            return false
        }
        selectedAssetIds.append(id)
        selectedAssetsById[id] = asset
        refreshSelectionUI()
        return true
    }

    /// Updates ONLY the selection badges of currently visible cells in place
    /// without calling `reloadData()`, eliminating all thumbnail flicker.
    /// 仅就地刷新当前可见单元格的选中角标，不调用 `reloadData()`，彻底杜绝缩略图闪烁。
    private func updateVisibleSelectionBadges() {
        guard let album = currentAlbum else { return }
        for cell in collectionView.visibleCells {
            guard let thumbCell = cell as? MediaThumbnailCell,
                  let indexPath = collectionView.indexPath(for: thumbCell),
                  let idx = assetIndex(for: indexPath) else {
                continue
            }
            let asset = album.fetchResult.object(at: idx)
            let selIdx = selectedAssetIds.firstIndex(of: asset.localIdentifier)
            thumbCell.updateBadge(
                theme: config.theme,
                multiple: config.multiple,
                selectionIndex: selIdx
            )
        }
    }

    private func refreshSelectionUI() {
        updateVisibleSelectionBadges()
        let count = selectedAssetIds.count
        if count > 0 {
            confirmButton.setTitle("\(config.strings.done) (\(count))", for: .normal)
            if bottomBar.isHidden {
                bottomBar.isHidden = false
                bottomBar.alpha = 0
                bottomBar.transform = CGAffineTransform(translationX: 0, y: 36)
                UIView.animate(withDuration: 0.2) {
                    self.bottomBar.alpha = 1
                    self.bottomBar.transform = .identity
                }
            }
        } else if !bottomBar.isHidden {
            UIView.animate(withDuration: 0.16, animations: {
                self.bottomBar.alpha = 0
                self.bottomBar.transform = CGAffineTransform(translationX: 0, y: 36)
            }, completion: { _ in
                self.bottomBar.isHidden = true
            })
        }
    }

    private func stopVisibleCameraCells() {
        for cell in collectionView.visibleCells {
            (cell as? CameraPreviewCell)?.stopSession()
        }
    }

    // MARK: - UICollectionViewDataSource & Delegate

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        hasHeroCameraSection() ? 2 : 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let album = currentAlbum else { return 0 }
        if hasHeroCameraSection() {
            if section == 0 {
                return 1 + min(album.count, heroRightCapacity())
            }
            return max(0, album.count - heroRightCapacity())
        }
        return album.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if hasHeroCameraSection(), indexPath.section == 0, indexPath.item == 0 {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CameraPreviewCell.reuseId,
                for: indexPath
            ) as? CameraPreviewCell else {
                return UICollectionViewCell()
            }
            cell.configure(cameraLabel: config.strings.cameraLabel)
            return cell
        }

        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MediaThumbnailCell.reuseId,
            for: indexPath
        ) as? MediaThumbnailCell,
              let album = currentAlbum,
              let idx = assetIndex(for: indexPath)
        else {
            return UICollectionViewCell()
        }

        let asset = album.fetchResult.object(at: idx)
        let selectionIndex = selectedAssetIds.firstIndex(of: asset.localIdentifier)
        cell.configure(
            asset: asset,
            repository: repository,
            theme: config.theme,
            multiple: config.multiple,
            selectionIndex: selectionIndex
        ) { [weak self] in
            guard let self = self else { return }
            if !self.config.multiple {
                _ = self.toggleSelection(for: asset)
                self.handleConfirmSelection()
            } else {
                _ = self.toggleSelection(for: asset)
            }
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if hasHeroCameraSection(), indexPath.section == 0, indexPath.item == 0 {
            deliveredResult = true
            dismissAnimated {
                self.onLaunchCamera()
            }
            return
        }

        guard let album = currentAlbum, let idx = assetIndex(for: indexPath) else { return }
        let asset = album.fetchResult.object(at: idx)
        if config.enablePreview {
            let preview = CustomMediaPreviewViewController(
                config: config,
                repository: repository,
                assets: album.fetchResult,
                initialIndex: idx,
                selectedIdsProvider: { [weak self] in self?.selectedAssetIds ?? [] },
                onToggleSelection: { [weak self] target in
                    self?.toggleSelection(for: target) ?? false
                },
                onConfirmSelection: { [weak self] in
                    self?.handleConfirmSelection()
                }
            )
            present(preview, animated: true)
        } else if !config.multiple {
            _ = toggleSelection(for: asset)
            handleConfirmSelection()
        } else {
            _ = toggleSelection(for: asset)
        }
    }

    // MARK: - Scroll Tracking & Fast Scroller / 滚动联动与日期浮窗

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Keep grid pinned to top while sheet is being dragged so content never jumps.
        // 拖拽抽屉期间锁定列表在顶部，避免与抽屉位移动画打架。
        if isDraggingSheet || currentSheetOffsetY > 2.0 {
            let topRest = -scrollView.contentInset.top
            if scrollView.contentOffset.y != topRest {
                scrollView.contentOffset = CGPoint(x: 0, y: topRest)
            }
            fastScrollThumb.isHidden = true
            return
        }

        let total = currentAlbum?.count ?? 0
        let shouldShowThumb = total > config.crossAxisCount * 5
        fastScrollThumb.isHidden = !shouldShowThumb
        guard shouldShowThumb else { return }

        let maxOffset = max(1, scrollView.contentSize.height - scrollView.bounds.height)
        let fraction = min(max(0, (scrollView.contentOffset.y + scrollView.contentInset.top) / maxOffset), 1)
        let trackTop: CGFloat = 64
        let trackBottom = max(trackTop + 1, sheetContainer.bounds.height - 160)
        fastScrollTopConstraint.constant = trackTop + fraction * (trackBottom - trackTop)

        if scrollView.isDragging || scrollView.isDecelerating {
            updateDateBubble(show: true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleHideDateBubble()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleHideDateBubble() }
    }

    private func updateDateBubble(show: Bool) {
        guard show, let album = currentAlbum, album.count > 0 else { return }
        let sortedPaths = collectionView.indexPathsForVisibleItems.sorted()
        let firstAssetIdx = sortedPaths.compactMap { assetIndex(for: $0) }.first ?? 0
        let asset = album.fetchResult.object(at: min(firstAssetIdx, album.count - 1))
        let text = PhotoLibraryRepository.formatMonthYear(asset.creationDate)
        guard !text.isEmpty else { return }

        dateBubbleHideWorkItem?.cancel()
        dateBubbleLabel.text = "  \(text)  "
        if dateBubbleLabel.isHidden {
            dateBubbleLabel.isHidden = false
            UIView.animate(withDuration: 0.14) { self.dateBubbleLabel.alpha = 1 }
        }
    }

    private func scheduleHideDateBubble() {
        dateBubbleHideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.2, animations: {
                self.dateBubbleLabel.alpha = 0
            }, completion: { _ in
                self.dateBubbleLabel.isHidden = true
            })
        }
        dateBubbleHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }
}

/// Grid cell displaying a single media thumbnail, optional video duration pill,
/// and interactive top-right circular selection badge.
/// 网格缩略图单元格：展示媒体封面、视频时长标签以及右上角可点击圆形选择角标。
private final class MediaThumbnailCell: UICollectionViewCell {
    static let reuseId = "XueHuaMediaThumbnailCell"

    private let imageView = UIImageView()
    private let durationLabel = UILabel()
    private let badgeHitButton = UIButton(type: .custom)
    private let badgeCircle = UIView()
    private let badgeLabel = UILabel()
    private let badgeCheckIcon = UIImageView()

    private var requestId: PHImageRequestID = PHInvalidImageRequestID
    private var assetId: String = ""
    private var onBadgeTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.gray.withAlphaComponent(0.18)
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        durationLabel.font = .systemFont(ofSize: 11, weight: .medium)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        durationLabel.layer.cornerRadius = 5
        durationLabel.clipsToBounds = true
        durationLabel.isHidden = true
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)

        badgeHitButton.translatesAutoresizingMaskIntoConstraints = false
        badgeHitButton.addTarget(self, action: #selector(handleBadgeTap), for: .touchUpInside)
        contentView.addSubview(badgeHitButton)

        badgeCircle.layer.cornerRadius = 12
        badgeCircle.clipsToBounds = true
        badgeCircle.isUserInteractionEnabled = false
        badgeCircle.translatesAutoresizingMaskIntoConstraints = false
        badgeHitButton.addSubview(badgeCircle)

        badgeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeCircle.addSubview(badgeLabel)

        badgeCheckIcon.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        )
        badgeCheckIcon.contentMode = .scaleAspectFit
        badgeCheckIcon.isHidden = true
        badgeCheckIcon.translatesAutoresizingMaskIntoConstraints = false
        badgeCircle.addSubview(badgeCheckIcon)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            durationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            badgeHitButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            badgeHitButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            badgeHitButton.widthAnchor.constraint(equalToConstant: 40),
            badgeHitButton.heightAnchor.constraint(equalToConstant: 40),

            badgeCircle.topAnchor.constraint(equalTo: badgeHitButton.topAnchor, constant: 6),
            badgeCircle.trailingAnchor.constraint(equalTo: badgeHitButton.trailingAnchor, constant: -6),
            badgeCircle.widthAnchor.constraint(equalToConstant: 24),
            badgeCircle.heightAnchor.constraint(equalToConstant: 24),

            badgeLabel.centerXAnchor.constraint(equalTo: badgeCircle.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeCircle.centerYAnchor),

            badgeCheckIcon.centerXAnchor.constraint(equalTo: badgeCircle.centerXAnchor),
            badgeCheckIcon.centerYAnchor.constraint(equalTo: badgeCircle.centerYAnchor),
            badgeCheckIcon.widthAnchor.constraint(equalToConstant: 14),
            badgeCheckIcon.heightAnchor.constraint(equalToConstant: 14),
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
        durationLabel.isHidden = true
        onBadgeTap = nil
    }

    func configure(
        asset: PHAsset,
        repository: PhotoLibraryRepository,
        theme: CustomMediaPickerTheme,
        multiple: Bool,
        selectionIndex: Int?,
        onBadgeTap: @escaping () -> Void
    ) {
        self.assetId = asset.localIdentifier
        self.onBadgeTap = onBadgeTap

        let scale = UIScreen.main.scale
        let side = max(contentView.bounds.width, 120) * scale
        requestId = repository.requestThumbnail(for: asset, targetSize: CGSize(width: side, height: side)) { [weak self] img in
            DispatchQueue.main.async {
                if self?.assetId == asset.localIdentifier, let img = img {
                    self?.imageView.image = img
                }
            }
        }

        if asset.mediaType == .video {
            durationLabel.text = " \(PhotoLibraryRepository.formatDuration(asset.duration)) "
            durationLabel.isHidden = false
        } else {
            durationLabel.isHidden = true
        }

        updateBadge(theme: theme, multiple: multiple, selectionIndex: selectionIndex)
    }

    /// Updates only the circular selection badge without touching the thumbnail image.
    /// 仅更新右上角选择角标，不触碰已加载的缩略图，避免闪烁。
    func updateBadge(theme: CustomMediaPickerTheme, multiple: Bool, selectionIndex: Int?) {
        if let selIdx = selectionIndex {
            badgeCircle.backgroundColor = theme.primaryColor
            badgeCircle.layer.borderWidth = 0
            if multiple {
                badgeCheckIcon.isHidden = true
                badgeLabel.isHidden = false
                badgeLabel.text = "\(selIdx + 1)"
                badgeLabel.textColor = theme.onPrimaryColor
            } else {
                badgeLabel.isHidden = true
                badgeCheckIcon.isHidden = false
                badgeCheckIcon.tintColor = theme.onPrimaryColor
            }
        } else {
            badgeLabel.isHidden = true
            badgeCheckIcon.isHidden = true
            badgeCircle.backgroundColor = theme.unselectedBadgeFillColor
            badgeCircle.layer.borderWidth = 1.8
            badgeCircle.layer.borderColor = theme.unselectedBadgeBorderColor.cgColor
        }
    }

    @objc private func handleBadgeTap() {
        onBadgeTap?()
    }
}
