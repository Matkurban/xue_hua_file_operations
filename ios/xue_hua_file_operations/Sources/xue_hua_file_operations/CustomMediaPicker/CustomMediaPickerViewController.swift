import Photos
import PhotosUI
import UIKit

/// Customizable native sheet-style media picker for iOS (iOS 14.0+).
/// Supports an expandable half-to-fullscreen sheet container, floating pill top bar,
/// album dropdown popover, overflow menu ("Open in other app..."), optional 1x2 live
/// camera preview tile, right-edge fast scroller with floating month-year bubble,
/// iOS 14+ limited photo access banner, full-screen preview, and bottom confirmation bar.
///
/// iOS 端可自定义样式的原生抽屉式媒体选择器（兼容 iOS 14.0+）。
/// 支持半屏上拉展开至全屏、顶部悬浮胶囊栏、相册下拉浮窗、更多菜单（使用其它应用打开…）、
/// 可配置的左上角 1×2 实时相机预览格、右侧快滑与日期浮窗、iOS 14+ 有限授权提示条、
/// 全屏预览页及底部确认栏。
final class CustomMediaPickerViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
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

    private var isExpanded: Bool
    private var hasAnimatedEntrance = false
    private var collapsedTopOffset: CGFloat = 0
    private var sheetTopConstraint: NSLayoutConstraint!
    private var deliveredResult = false

    private let scrimView = UIView()
    private let sheetContainer = UIView()
    private let dragHandleArea = UIView()
    private let dragHandlePill = UIView()
    private let limitedBanner = UIView()
    private let gridContainer = UIView()
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
    private let selectedCountLabel = UILabel()
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
        self.isExpanded = config.initialExpanded
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
        collapsedTopOffset = UIScreen.main.bounds.height * 0.40

        setupScrimAndSheet()
        setupDragHandle()
        setupLimitedBannerIfNeeded()
        setupGridAndCollectionView()
        setupFloatingTopBar()
        setupFastScroller()
        setupBottomBar()
        setupEmptyOrDeniedState()
        applyExpansionVisuals(progress: isExpanded ? 1.0 : 0.0)

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
        sheetTopConstraint.constant = isExpanded ? 0 : collapsedTopOffset
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut]
        ) {
            self.scrimView.alpha = 1.0
            self.view.layoutIfNeeded()
        }
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
            applyExpansionVisuals(progress: isExpanded ? 1.0 : 0.0)
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

        sheetContainer.backgroundColor = config.theme.backgroundColor
        sheetContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetContainer.layer.cornerRadius = isExpanded ? 0 : config.theme.sheetCornerRadius
        sheetContainer.clipsToBounds = true
        sheetContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheetContainer)

        // Start off-screen for smooth slide-up entrance / 初始置于屏幕底部以便平滑滑入
        sheetTopConstraint = sheetContainer.topAnchor.constraint(
            equalTo: view.topAnchor,
            constant: UIScreen.main.bounds.height
        )

        NSLayoutConstraint.activate([
            scrimView.topAnchor.constraint(equalTo: view.topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetTopConstraint,
            sheetContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupDragHandle() {
        dragHandleArea.translatesAutoresizingMaskIntoConstraints = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSheetPan(_:)))
        dragHandleArea.addGestureRecognizer(pan)
        sheetContainer.addSubview(dragHandleArea)

        dragHandlePill.backgroundColor = config.theme.handleColor
        dragHandlePill.layer.cornerRadius = 2.5
        dragHandlePill.translatesAutoresizingMaskIntoConstraints = false
        dragHandleArea.addSubview(dragHandlePill)

        NSLayoutConstraint.activate([
            dragHandleArea.topAnchor.constraint(equalTo: sheetContainer.safeAreaLayoutGuide.topAnchor),
            dragHandleArea.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            dragHandleArea.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            dragHandleArea.heightAnchor.constraint(equalToConstant: 26),

            dragHandlePill.centerXAnchor.constraint(equalTo: dragHandleArea.centerXAnchor),
            dragHandlePill.centerYAnchor.constraint(equalTo: dragHandleArea.centerYAnchor),
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

        NSLayoutConstraint.activate([
            limitedBanner.topAnchor.constraint(equalTo: dragHandleArea.bottomAnchor),
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

    private func setupGridAndCollectionView() {
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(gridContainer)

        let topAnchor = authStatus == .limited ? limitedBanner.bottomAnchor : dragHandleArea.bottomAnchor
        NSLayoutConstraint.activate([
            gridContainer.topAnchor.constraint(equalTo: topAnchor),
            gridContainer.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            gridContainer.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            gridContainer.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor),
        ])

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCompositionalLayout())
        collectionView.backgroundColor = config.theme.backgroundColor
        collectionView.contentInset = UIEdgeInsets(top: 62, left: 0, bottom: 92, right: 0)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MediaThumbnailCell.self, forCellWithReuseIdentifier: MediaThumbnailCell.reuseId)
        collectionView.register(CameraPreviewCell.self, forCellWithReuseIdentifier: CameraPreviewCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: gridContainer.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: gridContainer.bottomAnchor),
        ])
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

                let heroHeightFrac = (2.0 / cols)
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
        gridContainer.addSubview(topBar)

        let backIcon = UIImage(
            systemName: "arrow.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        styleFloatingPill(backButton, cornerRadius: 21)
        backButton.setImage(backIcon, for: .normal)
        backButton.tintColor = config.theme.iconColor
        backButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
        topBar.addSubview(backButton)

        // Album dropdown pill with native SF Symbol chevron.down / 带原生 SF Symbol 下拉箭头的相册胶囊按钮
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
            topBar.topAnchor.constraint(equalTo: gridContainer.topAnchor, constant: 6),
            topBar.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor, constant: 14),
            topBar.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor, constant: -14),
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
        gridContainer.addSubview(fastScrollThumb)

        dateBubbleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        dateBubbleLabel.textColor = config.theme.dateBubbleTextColor
        dateBubbleLabel.backgroundColor = config.theme.dateBubbleBackgroundColor
        dateBubbleLabel.layer.cornerRadius = 16
        dateBubbleLabel.clipsToBounds = true
        dateBubbleLabel.textAlignment = .center
        dateBubbleLabel.alpha = 0
        dateBubbleLabel.isHidden = true
        dateBubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.addSubview(dateBubbleLabel)

        fastScrollTopConstraint = fastScrollThumb.topAnchor.constraint(
            equalTo: gridContainer.topAnchor,
            constant: 68
        )

        NSLayoutConstraint.activate([
            fastScrollTopConstraint,
            fastScrollThumb.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor, constant: -6),
            fastScrollThumb.widthAnchor.constraint(equalToConstant: 38),
            fastScrollThumb.heightAnchor.constraint(equalToConstant: 38),

            dateBubbleLabel.centerYAnchor.constraint(equalTo: fastScrollThumb.centerYAnchor),
            dateBubbleLabel.trailingAnchor.constraint(equalTo: fastScrollThumb.leadingAnchor, constant: -10),
            dateBubbleLabel.heightAnchor.constraint(equalToConstant: 32),
            dateBubbleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 108),
        ])
    }

    private func setupBottomBar() {
        bottomBar.backgroundColor = config.theme.surfaceColor
        bottomBar.layer.shadowColor = UIColor.black.cgColor
        bottomBar.layer.shadowOpacity = 0.1
        bottomBar.layer.shadowRadius = 8
        bottomBar.layer.shadowOffset = CGSize(width: 0, height: -2)
        bottomBar.isHidden = true
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.addSubview(bottomBar)

        selectedCountLabel.font = .systemFont(ofSize: 14, weight: .medium)
        selectedCountLabel.textColor = config.theme.textColor
        selectedCountLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(selectedCountLabel)

        confirmButton.backgroundColor = config.theme.primaryColor
        confirmButton.setTitleColor(config.theme.onPrimaryColor, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        confirmButton.layer.cornerRadius = 20
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(handleConfirmSelection), for: .touchUpInside)
        bottomBar.addSubview(confirmButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: gridContainer.bottomAnchor),

            selectedCountLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 18),
            selectedCountLabel.centerYAnchor.constraint(equalTo: confirmButton.centerYAnchor),

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

        gridContainer.addSubview(emptyStateStack)
        NSLayoutConstraint.activate([
            emptyStateStack.centerXAnchor.constraint(equalTo: gridContainer.centerXAnchor),
            emptyStateStack.centerYAnchor.constraint(equalTo: gridContainer.centerYAnchor),
            emptyStateStack.leadingAnchor.constraint(greaterThanOrEqualTo: gridContainer.leadingAnchor, constant: 32),
            emptyStateStack.trailingAnchor.constraint(lessThanOrEqualTo: gridContainer.trailingAnchor, constant: -32),
        ])
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
                if indexPath.item == 0 { return nil } // Camera tile / 相机格
                let idx = indexPath.item - 1
                return idx < album.count ? idx : nil
            } else {
                let idx = heroRightCapacity() + indexPath.item
                return idx < album.count ? idx : nil
            }
        }
        return indexPath.item < album.count ? indexPath.item : nil
    }

    // MARK: - Actions & Gestures / 交互与手势

    private func dismissAnimated(completion: @escaping () -> Void) {
        stopVisibleCameraCells()
        sheetTopConstraint.constant = UIScreen.main.bounds.height
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn], animations: {
            self.scrimView.alpha = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.dismiss(animated: false, completion: completion)
        })
    }

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

    private func applyExpansionVisuals(progress: CGFloat) {
        let p = min(max(progress, 0), 1)
        sheetContainer.layer.cornerRadius = config.theme.sheetCornerRadius * (1 - p)
        dragHandlePill.alpha = max(0, 1 - p * 1.6)
        let isDenied = authStatus != .authorized && authStatus != .limited
        let topBarAlpha: CGFloat = isDenied ? 1.0 : min(max((p - 0.35) / 0.65, 0), 1)
        topBar.alpha = topBarAlpha
        topBar.isUserInteractionEnabled = topBarAlpha > 0.1
        collectionView.contentInset = UIEdgeInsets(top: 62 * p, left: 0, bottom: 92, right: 0)
    }

    @objc private func handleSheetPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let baseOffset: CGFloat = isExpanded ? 0 : collapsedTopOffset
        switch gesture.state {
        case .changed:
            let y = max(0, baseOffset + translation.y)
            sheetTopConstraint.constant = y
            let progress = 1.0 - min(max(y / max(collapsedTopOffset, 1), 0), 1)
            applyExpansionVisuals(progress: progress)
        case .ended, .cancelled:
            let currentY = sheetTopConstraint.constant
            if currentY < collapsedTopOffset * 0.55 {
                animateSheet(expanded: true)
            } else if currentY > collapsedTopOffset + view.bounds.height * 0.16 {
                handleCancel()
            } else {
                animateSheet(expanded: false)
            }
        default:
            break
        }
    }

    private func animateSheet(expanded: Bool) {
        isExpanded = expanded
        sheetTopConstraint.constant = expanded ? 0 : collapsedTopOffset
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.3,
            options: [.curveEaseOut]
        ) {
            self.applyExpansionVisuals(progress: expanded ? 1.0 : 0.0)
            self.view.layoutIfNeeded()
        }
    }

    @objc private func handleFastScrollPan(_ gesture: UIPanGestureRecognizer) {
        let trackTop: CGFloat = 68
        let trackBottom = max(trackTop + 1, gridContainer.bounds.height - 104)
        let locationY = gesture.location(in: gridContainer).y
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
    }

    @objc private func handleOpenInOtherAppTap() {
        dismissPopover()
        deliveredResult = true
        stopVisibleCameraCells()
        dismiss(animated: true) {
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
        stopVisibleCameraCells()
        dismiss(animated: true) {
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

    private func refreshSelectionUI() {
        collectionView.reloadData()
        let count = selectedAssetIds.count
        if count > 0 {
            bottomBar.isHidden = false
            let suffix = config.maxFiles.map { " / \($0)" } ?? ""
            selectedCountLabel.text = "\(count)\(suffix)"
            confirmButton.setTitle("\(config.strings.done) (\(count))", for: .normal)
        } else {
            bottomBar.isHidden = true
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
            stopVisibleCameraCells()
            dismiss(animated: true) {
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
        // Expand sheet automatically when user scrolls downward.
        // 用户向下浏览网格时自动平滑展开至全屏。
        if !isExpanded, scrollView.contentOffset.y > -scrollView.contentInset.top + 24 {
            animateSheet(expanded: true)
        }

        let total = currentAlbum?.count ?? 0
        let shouldShowThumb = total > config.crossAxisCount * 5
        fastScrollThumb.isHidden = !shouldShowThumb
        guard shouldShowThumb else { return }

        let maxOffset = max(1, scrollView.contentSize.height - scrollView.bounds.height)
        let fraction = min(max(0, (scrollView.contentOffset.y + scrollView.contentInset.top) / maxOffset), 1)
        let trackTop: CGFloat = 68
        let trackBottom = max(trackTop + 1, gridContainer.bounds.height - 104)
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
