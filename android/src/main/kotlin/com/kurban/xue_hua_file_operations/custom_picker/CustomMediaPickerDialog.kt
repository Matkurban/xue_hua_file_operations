package com.kurban.xue_hua_file_operations.custom_picker

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.kurban.xue_hua_file_operations.R
import kotlin.concurrent.thread
import kotlin.math.roundToInt

/**
 * Customizable native sheet-style media picker for Android.
 * Features edge-to-edge translucent system bars, fluid open/close/expand animations,
 * half-sheet to fullscreen transition (with floating pill top bar fading in on expand),
 * album dropdown popover, overflow menu ("Open in other app..."), optional 1x2 live
 * camera preview tile, right-edge fast scroller with floating month-year bubble,
 * full-screen preview dialog, and bottom confirmation bar.
 *
 * Android 端可自定义样式的原生抽屉式媒体选择器。
 * 支持沉浸式透明状态栏/导航栏、流畅的弹出/收起/展开动画、半屏到全屏平滑联动
 * （半屏隐藏悬浮顶栏、上拉全屏后渐显）、相册下拉浮窗、更多菜单（使用其它应用打开…）、
 * 可配置的左上角 1×2 实时相机预览格、右侧快速滚动与日期浮窗、全屏预览页及底部确认栏。
 */
class CustomMediaPickerDialog(
    private val hostActivity: Activity,
    private val config: CustomMediaPickerConfig,
    private var isLimitedAccess: Boolean,
    private var isPermissionDenied: Boolean,
    private val onResult: (List<Uri>?) -> Unit,
    private val onOpenInOtherApp: () -> Unit,
    private val onLaunchCamera: () -> Unit,
    private val onManageLimitedPermission: () -> Unit,
    private val onOpenAppSettings: () -> Unit,
    private val onRecheckPermission: () -> Pair<Boolean, Boolean>,
) : Dialog(hostActivity, android.R.style.Theme_Translucent_NoTitleBar) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val repository = MediaStoreRepository(hostActivity)
    private val sheetInterpolator = PathInterpolator(0.22f, 1f, 0.36f, 1f)

    private var albums: List<MediaAlbum> = emptyList()
    private var itemsByAlbum: Map<String, List<MediaItem>> = emptyMap()
    private var currentAlbumId: String = MediaAlbum.ID_ALL_MEDIA
    private var currentItems: List<MediaItem> = emptyList()
    private val selectedItems = ArrayList<MediaItem>()

    private var deliveredResult = false
    private var isDismissing = false
    private var isExpanded = config.initialExpanded
    private var expansionProgress = if (config.initialExpanded) 1f else 0f
    private var collapsedTopOffsetPx = 0
    private var screenHeightPx = 0
    private var screenWidthPx = 0
    private var cellSizePx = 0
    private var spacingPx = 0
    private var statusBarHeightPx = 0
    private var navBarHeightPx = 0

    private lateinit var scrimView: View
    private lateinit var sheetContainer: FrameLayout
    private lateinit var dragHandleContainer: FrameLayout
    private lateinit var limitedBanner: LinearLayout
    private lateinit var topBarContainer: FrameLayout
    private lateinit var albumTitleText: TextView
    private lateinit var recyclerView: RecyclerView
    private lateinit var emptyStateContainer: LinearLayout
    private lateinit var bottomConfirmBar: FrameLayout
    private lateinit var confirmButton: TextView
    private lateinit var selectedHintView: TextView
    private lateinit var fastScrollThumb: FrameLayout
    private lateinit var dateBubbleView: TextView
    private var activeCameraTile: CameraPreviewTileView? = null
    private var activePopup: PopupWindow? = null
    private var sheetAnimator: ValueAnimator? = null

    private val gridAdapter = MediaGridAdapter()
    private val hideDateBubbleRunnable = Runnable {
        dateBubbleView.animate().alpha(0f).setDuration(180).withEndAction {
            dateBubbleView.visibility = View.GONE
        }.start()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        configureEdgeToEdgeWindow()

        val metrics = hostActivity.resources.displayMetrics
        val density = metrics.density
        screenHeightPx = metrics.heightPixels
        screenWidthPx = metrics.widthPixels
        spacingPx = (config.theme.gridSpacingDp * density).roundToInt()
        cellSizePx = ((screenWidthPx - spacingPx * (config.crossAxisCount - 1)) / config.crossAxisCount)
            .coerceAtLeast(1)
        collapsedTopOffsetPx = (screenHeightPx * 0.40f).roundToInt()

        val root = FrameLayout(hostActivity).apply {
            clipChildren = false
            clipToPadding = false
        }

        // Dimmed backdrop scrim (animated separately from sheet)
        // 独立控制的背景半透明遮罩层（支持平滑淡入淡出）
        scrimView = View(hostActivity).apply {
            setBackgroundColor(config.theme.scrimColor)
            alpha = 0f
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setOnClickListener { dismissAnimated() }
        }
        root.addView(scrimView)

        sheetContainer = FrameLayout(hostActivity).apply {
            clipChildren = false
            clipToPadding = false
            isClickable = true
            isFocusable = true
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        root.addView(sheetContainer)

        val contentColumn = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
            clipChildren = false
            clipToPadding = false
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        sheetContainer.addView(contentColumn)

        // Drag handle area / 顶部拖拽指示条区域
        dragHandleContainer = buildDragHandleArea(density)
        contentColumn.addView(dragHandleContainer)

        // Limited-access banner (Android 14+ partial photo access)
        // Android 14+ 部分照片授权顶部提示条
        limitedBanner = buildLimitedAccessBanner(density)
        limitedBanner.visibility = if (isLimitedAccess && !isPermissionDenied) View.VISIBLE else View.GONE
        contentColumn.addView(limitedBanner)

        // Grid + floating overlays container / 媒体网格与悬浮控件容器
        val gridWrapper = FrameLayout(hostActivity).apply {
            clipChildren = false
            clipToPadding = false
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        contentColumn.addView(gridWrapper)

        val gridLayoutManager = GridLayoutManager(hostActivity, config.crossAxisCount).apply {
            spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
                override fun getSpanSize(position: Int): Int {
                    return if (hasHeroCameraHeader() && position == 0) config.crossAxisCount else 1
                }
            }
        }
        recyclerView = RecyclerView(hostActivity).apply {
            layoutManager = gridLayoutManager
            adapter = gridAdapter
            clipToPadding = false
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        attachScrollListeners()
        gridWrapper.addView(recyclerView)

        // Empty / Permission-denied state / 空态或无权限状态视图
        emptyStateContainer = buildEmptyOrDeniedView(density)
        gridWrapper.addView(emptyStateContainer)

        // Floating pill top bar (fades in smoothly when expanding to fullscreen)
        // 顶部悬浮胶囊操作栏（半屏时隐藏，上拉展开至全屏时平滑渐显）
        topBarContainer = buildFloatingTopBar(density)
        gridWrapper.addView(topBarContainer)

        // Fast-scroll thumb & floating date bubble / 右侧快滑手柄与月份年份浮窗
        buildFastScrollerOverlays(gridWrapper, density)

        // Bottom confirmation bar / 底部选中确认栏
        bottomConfirmBar = buildBottomConfirmBar(density)
        gridWrapper.addView(bottomConfirmBar)

        // Listen for real system status bar & navigation bar insets
        // 动态监听系统状态栏与底部导航栏安全区域
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            statusBarHeightPx = bars.top
            navBarHeightPx = bars.bottom
            applyInsetsAndExpansion(expansionProgress)
            insets
        }

        setContentView(root)
        setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                dismissAnimated()
                true
            } else {
                false
            }
        }
        setOnDismissListener {
            sheetAnimator?.cancel()
            activePopup?.dismiss()
            activeCameraTile?.stopPreview()
            repository.release()
            if (!deliveredResult) {
                deliveredResult = true
                onResult(null)
            }
        }

        // Start off-screen and animate smoothly upward / 从屏幕底部平滑弹出
        sheetContainer.translationY = screenHeightPx.toFloat()
        applyInsetsAndExpansion(if (isExpanded) 1f else 0f)
        root.post {
            animateEntrance()
        }

        if (isPermissionDenied) {
            showDeniedState()
        } else {
            loadMediaAsync()
        }
    }

    /**
     * Re-checks media read permissions when the dialog regains focus
     * (e.g. after returning from Android App Settings).
     * 弹窗重新获得焦点时（例如从系统设置页返回后）自动重新检查相册权限并刷新列表。
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || !isShowing) return
        val (denied, limited) = onRecheckPermission()
        if (isPermissionDenied && !denied) {
            isPermissionDenied = false
            isLimitedAccess = limited
            limitedBanner.visibility = if (limited) View.VISIBLE else View.GONE
            emptyStateContainer.visibility = View.GONE
            recyclerView.visibility = View.VISIBLE
            loadMediaAsync()
        } else if (!denied && limited != isLimitedAccess) {
            isLimitedAccess = limited
            limitedBanner.visibility = if (limited) View.VISIBLE else View.GONE
            loadMediaAsync()
        }
    }

    /**
     * Reloads media items after the user updates limited photo permissions.
     * 用户在 Android 14+ 部分授权管理后重新加载媒体列表。
     */
    fun reloadMedia() {
        if (!isShowing) return
        val (denied, limited) = onRecheckPermission()
        isPermissionDenied = denied
        isLimitedAccess = limited
        limitedBanner.visibility = if (limited && !denied) View.VISIBLE else View.GONE
        if (!denied) {
            loadMediaAsync()
        }
    }

    private fun configureEdgeToEdgeWindow() {
        val win = window ?: return
        win.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        win.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        WindowCompat.setDecorFitsSystemWindows(win, false)
        win.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        @Suppress("DEPRECATION")
        win.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        win.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            win.attributes = win.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        val controller = WindowCompat.getInsetsController(win, win.decorView)
        controller.isAppearanceLightStatusBars = !config.theme.isDark
        controller.isAppearanceLightNavigationBars = !config.theme.isDark
    }

    private fun animateEntrance() {
        scrimView.animate()
            .alpha(1f)
            .setDuration(240)
            .setInterpolator(DecelerateInterpolator())
            .start()

        val targetY = if (isExpanded) 0f else collapsedTopOffsetPx.toFloat()
        sheetContainer.animate()
            .translationY(targetY)
            .setDuration(300)
            .setInterpolator(sheetInterpolator)
            .start()
    }

    private fun dismissAnimated(afterDismiss: (() -> Unit)? = null) {
        if (isDismissing) return
        isDismissing = true
        activePopup?.dismiss()
        sheetAnimator?.cancel()

        scrimView.animate()
            .alpha(0f)
            .setDuration(200)
            .setInterpolator(DecelerateInterpolator())
            .start()

        sheetContainer.animate()
            .translationY(screenHeightPx.toFloat())
            .setDuration(230)
            .setInterpolator(DecelerateInterpolator())
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    super@CustomMediaPickerDialog.dismiss()
                    afterDismiss?.invoke()
                }
            })
            .start()
    }

    private fun dp(value: Int): Int = (value * hostActivity.resources.displayMetrics.density).roundToInt()

    private fun applyInsetsAndExpansion(progress: Float) {
        expansionProgress = progress.coerceIn(0f, 1f)
        val density = hostActivity.resources.displayMetrics.density

        // Interpolate top corner radius smoothly (rounded in half-sheet -> square in fullscreen)
        // 平滑插值顶部圆角（半屏圆角 -> 全屏直角）
        val radius = config.theme.sheetCornerRadiusDp * density * (1f - expansionProgress)
        sheetContainer.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(config.theme.backgroundColor)
            cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
        }

        // Drag handle height & alpha shrink smoothly when expanded to fullscreen
        // 展开至全屏时平滑收缩拖拽条并让出状态栏安全区
        val handleHeight = ((26 * density) * (1f - expansionProgress)).roundToInt()
        val handleLp = dragHandleContainer.layoutParams as LinearLayout.LayoutParams
        handleLp.height = handleHeight
        dragHandleContainer.layoutParams = handleLp
        dragHandleContainer.alpha = (1f - expansionProgress * 1.6f).coerceIn(0f, 1f)

        // Floating top bar fades in smoothly as the sheet expands (hidden in half-sheet!)
        // 顶部悬浮胶囊栏在半屏状态下隐藏，上拉展开过程中平滑渐显
        val topBarAlpha = if (isPermissionDenied) {
            1f
        } else {
            ((expansionProgress - 0.35f) / 0.65f).coerceIn(0f, 1f)
        }
        topBarContainer.alpha = topBarAlpha
        topBarContainer.visibility = if (topBarAlpha > 0.02f) View.VISIBLE else View.INVISIBLE
        topBarContainer.translationY = -(1f - topBarAlpha) * (16 * density)

        val topBarTopPad = (statusBarHeightPx * expansionProgress).roundToInt() + dp(10)
        topBarContainer.setPadding(dp(14), topBarTopPad, dp(14), dp(14))

        // Adjust RecyclerView padding cleanly for both half-sheet and fullscreen
        // 动态调整网格上下内边距（半屏紧贴顶部圆角，全屏预留悬浮栏空间）
        val gridTopPad = ((statusBarHeightPx + dp(62)) * expansionProgress).roundToInt()
        val gridBottomPad = navBarHeightPx + dp(88)
        recyclerView.setPadding(0, gridTopPad, 0, gridBottomPad)

        // Adjust bottom confirm bar padding for navigation bar inset
        // 为底部确认栏适配系统底部导航栏安全区
        bottomConfirmBar.setPadding(dp(16), dp(12), dp(16), dp(16) + navBarHeightPx)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun buildDragHandleArea(density: Float): FrameLayout {
        val container = FrameLayout(hostActivity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (26 * density).roundToInt()
            )
        }
        val pill = View(hostActivity).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 3 * density
                setColor(config.theme.handleColor)
            }
            layoutParams = FrameLayout.LayoutParams(
                (40 * density).roundToInt(),
                (5 * density).roundToInt(),
                Gravity.CENTER
            )
        }
        container.addView(pill)

        var downRawY = 0f
        var startTranslationY = 0f
        container.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    sheetAnimator?.cancel()
                    downRawY = event.rawY
                    startTranslationY = sheetContainer.translationY
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val delta = event.rawY - downRawY
                    val target = (startTranslationY + delta).coerceAtLeast(0f)
                    sheetContainer.translationY = target
                    val progress = 1f - (target / collapsedTopOffsetPx.coerceAtLeast(1)).coerceIn(0f, 1f)
                    applyInsetsAndExpansion(progress)
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val currentY = sheetContainer.translationY
                    when {
                        currentY < collapsedTopOffsetPx * 0.55f -> animateSheetState(expanded = true)
                        currentY > collapsedTopOffsetPx + screenHeightPx * 0.16f -> dismissAnimated()
                        else -> animateSheetState(expanded = false)
                    }
                    true
                }

                else -> false
            }
        }
        return container
    }

    private fun animateSheetState(expanded: Boolean) {
        isExpanded = expanded
        sheetAnimator?.cancel()
        val startY = sheetContainer.translationY
        val endY = if (expanded) 0f else collapsedTopOffsetPx.toFloat()
        val startProgress = expansionProgress
        val endProgress = if (expanded) 1f else 0f

        sheetAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 260
            interpolator = sheetInterpolator
            addUpdateListener { anim ->
                val f = anim.animatedValue as Float
                sheetContainer.translationY = startY + (endY - startY) * f
                applyInsetsAndExpansion(startProgress + (endProgress - startProgress) * f)
            }
            start()
        }
    }

    private fun buildLimitedAccessBanner(density: Float): LinearLayout {
        return LinearLayout(hostActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(config.theme.surfaceColor)
            setPadding((16 * density).roundToInt(), (10 * density).roundToInt(), (16 * density).roundToInt(), (10 * density).roundToInt())
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )

            addView(TextView(hostActivity).apply {
                text = config.strings.limitedAccessHint
                textSize = 13f
                setTextColor(config.theme.secondaryTextColor)
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            })

            addView(TextView(hostActivity).apply {
                text = config.strings.managePermission
                textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(config.theme.primaryColor)
                setPadding((12 * density).roundToInt(), (4 * density).roundToInt(), 0, (4 * density).roundToInt())
                setOnClickListener { onManageLimitedPermission() }
            })
        }
    }

    private fun makeFloatingSurfaceDrawable(density: Float, isOval: Boolean): GradientDrawable {
        val strokeColor = if (config.theme.isDark) 0x22FFFFFF else 0x16000000
        return GradientDrawable().apply {
            shape = if (isOval) GradientDrawable.OVAL else GradientDrawable.RECTANGLE
            if (!isOval) cornerRadius = 22 * density
            setColor(config.theme.surfaceColor)
            setStroke((1 * density).roundToInt().coerceAtLeast(1), strokeColor)
        }
    }

    private fun buildFloatingTopBar(density: Float): FrameLayout {
        val bar = FrameLayout(hostActivity).apply {
            clipChildren = false
            clipToPadding = false
            setPadding((14 * density).roundToInt(), (12 * density).roundToInt(), (14 * density).roundToInt(), (14 * density).roundToInt())
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val btnSize = (42 * density).roundToInt()
        val iconSize = (22 * density).roundToInt()
        val elevationPx = 5 * density

        // Back / close circular vector icon button / 左侧圆形返回矢量图标按钮
        val backBtn = FrameLayout(hostActivity).apply {
            elevation = elevationPx
            background = makeFloatingSurfaceDrawable(density, isOval = true)
            layoutParams = FrameLayout.LayoutParams(btnSize, btnSize, Gravity.START or Gravity.CENTER_VERTICAL)
            addView(ImageView(hostActivity).apply {
                setImageResource(R.drawable.xh_ic_arrow_back)
                setColorFilter(config.theme.iconColor, PorterDuff.Mode.SRC_IN)
                layoutParams = FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER)
            })
            setOnClickListener { dismissAnimated() }
        }
        bar.addView(backBtn)

        // Center album dropdown pill with vector chevron / 居中相册切换胶囊（文本 + 矢量下拉箭头）
        val albumPill = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            elevation = elevationPx
            setPadding((18 * density).roundToInt(), 0, (12 * density).roundToInt(), 0)
            background = makeFloatingSurfaceDrawable(density, isOval = false)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                btnSize,
                Gravity.CENTER
            ).apply {
                marginStart = (64 * density).roundToInt()
                marginEnd = (64 * density).roundToInt()
            }
            setOnClickListener { showAlbumDropdown(this) }
        }

        albumTitleText = TextView(hostActivity).apply {
            text = config.strings.galleryTitle
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.textColor)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        albumPill.addView(albumTitleText)

        albumPill.addView(ImageView(hostActivity).apply {
            setImageResource(R.drawable.xh_ic_arrow_drop_down)
            setColorFilter(config.theme.iconColor, PorterDuff.Mode.SRC_IN)
            val arrowSize = (20 * density).roundToInt()
            layoutParams = LinearLayout.LayoutParams(arrowSize, arrowSize).apply {
                marginStart = (2 * density).roundToInt()
            }
        })
        bar.addView(albumPill)

        // Right overflow vector icon button / 右侧更多操作矢量图标按钮
        if (config.allowOpenInOtherApp) {
            val moreBtn = FrameLayout(hostActivity).apply {
                elevation = elevationPx
                background = makeFloatingSurfaceDrawable(density, isOval = true)
                layoutParams = FrameLayout.LayoutParams(btnSize, btnSize, Gravity.END or Gravity.CENTER_VERTICAL)
                addView(ImageView(hostActivity).apply {
                    setImageResource(R.drawable.xh_ic_more_vert)
                    setColorFilter(config.theme.iconColor, PorterDuff.Mode.SRC_IN)
                    layoutParams = FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER)
                })
                setOnClickListener { showOverflowMenu(this) }
            }
            bar.addView(moreBtn)
        }

        return bar
    }

    private fun showAlbumDropdown(anchor: View) {
        if (albums.isEmpty()) return
        activePopup?.dismiss()
        val density = hostActivity.resources.displayMetrics.density

        val card = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, (8 * density).roundToInt(), 0, (8 * density).roundToInt())
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 18 * density
                setColor(config.theme.surfaceColor)
            }
            elevation = 12 * density
            alpha = 0f
            scaleX = 0.94f
            scaleY = 0.94f
        }

        val scrollView = ScrollView(hostActivity).apply {
            isVerticalScrollBarEnabled = false
        }
        val listLayout = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
        }

        for (album in albums) {
            val row = LinearLayout(hostActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(
                    (14 * density).roundToInt(),
                    (8 * density).roundToInt(),
                    (16 * density).roundToInt(),
                    (8 * density).roundToInt()
                )
                setOnClickListener {
                    selectAlbum(album)
                    activePopup?.dismiss()
                }
            }

            val thumbSize = (42 * density).roundToInt()
            val thumbView = ImageView(hostActivity).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                clipToOutline = true
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = 8 * density
                    setColor(0x22888888)
                }
                layoutParams = LinearLayout.LayoutParams(thumbSize, thumbSize)
            }
            album.coverUri?.let { cover ->
                repository.loadThumbnail(cover, thumbSize * 2, album.isAllVideos) { bmp ->
                    mainHandler.post { if (bmp != null) thumbView.setImageBitmap(bmp) }
                }
            }
            row.addView(thumbView)

            val titleView = TextView(hostActivity).apply {
                text = album.name
                textSize = 15f
                setTextColor(config.theme.textColor)
                typeface = if (album.id == currentAlbumId) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginStart = (12 * density).roundToInt()
                }
            }
            row.addView(titleView)

            val countView = TextView(hostActivity).apply {
                text = " ${album.count}"
                textSize = 14f
                setTextColor(config.theme.secondaryTextColor)
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginStart = (4 * density).roundToInt()
                }
            }
            row.addView(countView)

            listLayout.addView(row)
        }

        scrollView.addView(listLayout)
        val maxHeight = (screenHeightPx * 0.55f).roundToInt()
        card.addView(
            scrollView,
            LinearLayout.LayoutParams(
                (screenWidthPx * 0.68f).roundToInt(),
                minOf((albums.size * 58 * density).roundToInt(), maxHeight)
            )
        )

        val popup = PopupWindow(
            card,
            (screenWidthPx * 0.68f).roundToInt(),
            ViewGroup.LayoutParams.WRAP_CONTENT,
            true
        ).apply {
            isOutsideTouchable = true
            elevation = 16 * density
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        }
        activePopup = popup
        popup.showAsDropDown(anchor, -(screenWidthPx * 0.14f).roundToInt(), (6 * density).roundToInt())
        card.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(160).setInterpolator(DecelerateInterpolator()).start()
    }

    private fun showOverflowMenu(anchor: View) {
        activePopup?.dismiss()
        val density = hostActivity.resources.displayMetrics.density

        val card = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((14 * density).roundToInt(), (8 * density).roundToInt(), (16 * density).roundToInt(), (8 * density).roundToInt())
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 16 * density
                setColor(config.theme.surfaceColor)
            }
            elevation = 12 * density
            alpha = 0f
            scaleX = 0.94f
            scaleY = 0.94f
        }

        val itemRow = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((4 * density).roundToInt(), (10 * density).roundToInt(), (4 * density).roundToInt(), (10 * density).roundToInt())
            setOnClickListener {
                activePopup?.dismiss()
                deliveredResult = true
                dismissAnimated { onOpenInOtherApp() }
            }
        }
        itemRow.addView(ImageView(hostActivity).apply {
            setImageResource(R.drawable.xh_ic_open_in_new)
            setColorFilter(config.theme.iconColor, PorterDuff.Mode.SRC_IN)
            val iconPx = (20 * density).roundToInt()
            layoutParams = LinearLayout.LayoutParams(iconPx, iconPx).apply {
                marginEnd = (12 * density).roundToInt()
            }
        })
        itemRow.addView(TextView(hostActivity).apply {
            text = config.strings.openInOtherApp
            textSize = 15f
            setTextColor(config.theme.textColor)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        card.addView(itemRow)

        val popupWidth = (screenWidthPx * 0.62f).roundToInt()
        val popup = PopupWindow(card, popupWidth, ViewGroup.LayoutParams.WRAP_CONTENT, true).apply {
            isOutsideTouchable = true
            elevation = 16 * density
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        }
        activePopup = popup
        popup.showAsDropDown(anchor, -(popupWidth - anchor.width), (6 * density).roundToInt())
        card.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(160).setInterpolator(DecelerateInterpolator()).start()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun buildFastScrollerOverlays(parent: FrameLayout, density: Float) {
        dateBubbleView = TextView(hostActivity).apply {
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.dateBubbleTextColor)
            setPadding((14 * density).roundToInt(), (8 * density).roundToInt(), (14 * density).roundToInt(), (8 * density).roundToInt())
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 18 * density
                setColor(config.theme.dateBubbleBackgroundColor)
            }
            elevation = 8 * density
            visibility = View.GONE
            alpha = 0f
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.END
            ).apply {
                marginEnd = (54 * density).roundToInt()
                topMargin = (72 * density).roundToInt()
            }
        }
        parent.addView(dateBubbleView)

        val thumbSize = (38 * density).roundToInt()
        fastScrollThumb = FrameLayout(hostActivity).apply {
            background = makeFloatingSurfaceDrawable(density, isOval = true)
            elevation = 6 * density
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(thumbSize, thumbSize, Gravity.TOP or Gravity.END).apply {
                marginEnd = (6 * density).roundToInt()
                topMargin = (72 * density).roundToInt()
            }
            addView(ImageView(hostActivity).apply {
                setImageResource(R.drawable.xh_ic_fast_scroll)
                setColorFilter(config.theme.iconColor, PorterDuff.Mode.SRC_IN)
                val iconPx = (20 * density).roundToInt()
                layoutParams = FrameLayout.LayoutParams(iconPx, iconPx, Gravity.CENTER)
            })
        }

        fastScrollThumb.setOnTouchListener { _, event ->
            val trackTop = (72 * density) + statusBarHeightPx
            val trackBottom = (parent.height - 96 * density - navBarHeightPx).coerceAtLeast(trackTop + 1f)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    val parentLoc = IntArray(2)
                    parent.getLocationOnScreen(parentLoc)
                    val localY = (event.rawY - parentLoc[1]).coerceIn(trackTop, trackBottom)
                    val fraction = ((localY - trackTop) / (trackBottom - trackTop)).coerceIn(0f, 1f)
                    val targetPos = (fraction * (gridAdapter.itemCount - 1).coerceAtLeast(0)).roundToInt()
                    recyclerView.scrollToPosition(targetPos)
                    updateFastScrollPosition(fraction, showBubble = true)
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    scheduleHideDateBubble()
                    true
                }

                else -> false
            }
        }
        parent.addView(fastScrollThumb)
    }

    private fun attachScrollListeners() {
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                if (!isExpanded && dy > 12) {
                    animateSheetState(expanded = true)
                }
                val range = (rv.computeVerticalScrollRange() - rv.computeVerticalScrollExtent()).coerceAtLeast(1)
                val offset = rv.computeVerticalScrollOffset()
                val fraction = (offset.toFloat() / range.toFloat()).coerceIn(0f, 1f)
                val showThumb = currentItems.size > config.crossAxisCount * 5
                fastScrollThumb.visibility = if (showThumb) View.VISIBLE else View.GONE
                if (showThumb) {
                    updateFastScrollPosition(fraction, showBubble = rv.scrollState != RecyclerView.SCROLL_STATE_IDLE)
                }
            }

            override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    scheduleHideDateBubble()
                }
            }
        })
    }

    private fun updateFastScrollPosition(fraction: Float, showBubble: Boolean) {
        val density = hostActivity.resources.displayMetrics.density
        val parentHeight = (fastScrollThumb.parent as? View)?.height ?: return
        val trackTop = 72 * density + statusBarHeightPx
        val trackBottom = (parentHeight - 104 * density - navBarHeightPx).coerceAtLeast(trackTop + 1f)
        val y = trackTop + fraction * (trackBottom - trackTop)
        fastScrollThumb.translationY = y - (72 * density)
        dateBubbleView.translationY = y - (72 * density)

        val lm = recyclerView.layoutManager as? GridLayoutManager ?: return
        val firstVisible = lm.findFirstVisibleItemPosition().coerceAtLeast(0)
        val itemIndex = adapterPositionToItemIndex(firstVisible).coerceIn(0, (currentItems.size - 1).coerceAtLeast(0))
        val item = currentItems.getOrNull(itemIndex)
        if (showBubble && item != null) {
            val label = MediaStoreRepository.formatMonthYear(item.dateAddedSec)
            if (label.isNotEmpty()) {
                mainHandler.removeCallbacks(hideDateBubbleRunnable)
                dateBubbleView.text = label
                if (dateBubbleView.visibility != View.VISIBLE) {
                    dateBubbleView.visibility = View.VISIBLE
                    dateBubbleView.animate().alpha(1f).setDuration(120).start()
                }
            }
        }
    }

    private fun scheduleHideDateBubble() {
        mainHandler.removeCallbacks(hideDateBubbleRunnable)
        mainHandler.postDelayed(hideDateBubbleRunnable, 900)
    }

    private fun buildBottomConfirmBar(density: Float): FrameLayout {
        val bar = FrameLayout(hostActivity).apply {
            setBackgroundColor(config.theme.surfaceColor)
            elevation = 10 * density
            setPadding((16 * density).roundToInt(), (12 * density).roundToInt(), (16 * density).roundToInt(), (16 * density).roundToInt())
            visibility = View.GONE
            alpha = 0f
            translationY = 48 * density
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        selectedHintView = TextView(hostActivity).apply {
            textSize = 14f
            setTextColor(config.theme.textColor)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.START or Gravity.CENTER_VERTICAL
            )
        }
        bar.addView(selectedHintView)

        confirmButton = TextView(hostActivity).apply {
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.onPrimaryColor)
            gravity = Gravity.CENTER
            setPadding((22 * density).roundToInt(), (10 * density).roundToInt(), (22 * density).roundToInt(), (10 * density).roundToInt())
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 22 * density
                setColor(config.theme.primaryColor)
            }
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.END or Gravity.CENTER_VERTICAL
            )
            setOnClickListener { confirmAndFinish() }
        }
        bar.addView(confirmButton)
        return bar
    }

    private fun buildEmptyOrDeniedView(density: Float): LinearLayout {
        return LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            setPadding((32 * density).roundToInt(), 0, (32 * density).roundToInt(), 0)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
    }

    private fun showDeniedState() {
        val density = hostActivity.resources.displayMetrics.density
        emptyStateContainer.removeAllViews()
        emptyStateContainer.visibility = View.VISIBLE
        recyclerView.visibility = View.GONE
        applyInsetsAndExpansion(expansionProgress)

        emptyStateContainer.addView(TextView(hostActivity).apply {
            text = config.strings.permissionDeniedMessage
            textSize = 15f
            setTextColor(config.theme.secondaryTextColor)
            gravity = Gravity.CENTER
        })

        emptyStateContainer.addView(TextView(hostActivity).apply {
            text = config.strings.openSettings
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.onPrimaryColor)
            setPadding((22 * density).roundToInt(), (11 * density).roundToInt(), (22 * density).roundToInt(), (11 * density).roundToInt())
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 22 * density
                setColor(config.theme.primaryColor)
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = (18 * density).roundToInt()
            }
            setOnClickListener { onOpenAppSettings() }
        })
    }

    private fun showEmptyState() {
        emptyStateContainer.removeAllViews()
        emptyStateContainer.visibility = View.VISIBLE
        emptyStateContainer.addView(TextView(hostActivity).apply {
            text = config.strings.emptyAlbum
            textSize = 15f
            setTextColor(config.theme.secondaryTextColor)
            gravity = Gravity.CENTER
        })
    }

    private fun loadMediaAsync() {
        thread {
            val (loadedAlbums, loadedMap) = repository.loadMediaAndAlbums(config.mediaType, config.strings)
            mainHandler.post {
                if (!isShowing) return@post
                albums = loadedAlbums
                itemsByAlbum = loadedMap
                val targetAlbum = albums.firstOrNull { it.id == currentAlbumId } ?: albums.firstOrNull()
                if (targetAlbum != null) {
                    selectAlbum(targetAlbum)
                } else {
                    showEmptyState()
                }
            }
        }
    }

    private fun selectAlbum(album: MediaAlbum) {
        currentAlbumId = album.id
        currentItems = itemsByAlbum[album.id].orEmpty()
        albumTitleText.text = if (album.isAllMedia) config.strings.galleryTitle else album.name
        if (currentItems.isEmpty() && !hasHeroCameraHeader()) {
            recyclerView.visibility = View.GONE
            showEmptyState()
        } else {
            emptyStateContainer.visibility = View.GONE
            recyclerView.visibility = View.VISIBLE
        }
        gridAdapter.notifyDataSetChanged()
        recyclerView.scrollToPosition(0)
    }

    private fun hasHeroCameraHeader(): Boolean =
        config.showCameraTile && currentAlbumId == MediaAlbum.ID_ALL_MEDIA

    private fun heroRightItemCount(): Int =
        if (hasHeroCameraHeader()) minOf(currentItems.size, 2 * (config.crossAxisCount - 1)) else 0

    private fun adapterPositionToItemIndex(adapterPos: Int): Int {
        if (!hasHeroCameraHeader()) return adapterPos
        if (adapterPos == 0) return 0
        return heroRightItemCount() + (adapterPos - 1)
    }

    private fun toggleSelection(item: MediaItem): Boolean {
        val existingIdx = selectedItems.indexOfFirst { it.id == item.id }
        if (existingIdx >= 0) {
            selectedItems.removeAt(existingIdx)
            refreshSelectionUI()
            return true
        }
        if (!config.multiple) {
            selectedItems.clear()
            selectedItems.add(item)
            refreshSelectionUI()
            return true
        }
        val limit = config.maxFiles
        if (limit != null && selectedItems.size >= limit) {
            val msg = config.strings.maxSelectionReached.replace("{max}", limit.toString())
            Toast.makeText(hostActivity, msg, Toast.LENGTH_SHORT).show()
            return false
        }
        selectedItems.add(item)
        refreshSelectionUI()
        return true
    }

    private fun onThumbnailClicked(item: MediaItem, itemIndex: Int) {
        if (config.enablePreview) {
            CustomMediaPreviewDialog(
                context = hostActivity,
                config = config,
                repository = repository,
                items = currentItems,
                initialIndex = itemIndex,
                selectedItems = selectedItems,
                onToggleSelection = { target -> toggleSelection(target) },
                onConfirmSelection = { confirmAndFinish() },
            ).show()
        } else if (!config.multiple) {
            selectedItems.clear()
            selectedItems.add(item)
            confirmAndFinish()
        } else {
            toggleSelection(item)
        }
    }

    private fun onBadgeClicked(item: MediaItem) {
        if (!config.multiple) {
            selectedItems.clear()
            selectedItems.add(item)
            confirmAndFinish()
            return
        }
        toggleSelection(item)
    }

    private fun refreshSelectionUI() {
        gridAdapter.notifyDataSetChanged()
        val count = selectedItems.size
        val density = hostActivity.resources.displayMetrics.density
        if (count > 0) {
            val limitSuffix = config.maxFiles?.let { " / $it" } ?: ""
            selectedHintView.text = "$count$limitSuffix"
            confirmButton.text = "${config.strings.done} ($count)"
            if (bottomConfirmBar.visibility != View.VISIBLE) {
                bottomConfirmBar.visibility = View.VISIBLE
                bottomConfirmBar.animate().alpha(1f).translationY(0f).setDuration(180).start()
            }
        } else if (bottomConfirmBar.visibility == View.VISIBLE) {
            bottomConfirmBar.animate()
                .alpha(0f)
                .translationY(48 * density)
                .setDuration(160)
                .withEndAction { bottomConfirmBar.visibility = View.GONE }
                .start()
        }
    }

    private fun confirmAndFinish() {
        if (selectedItems.isEmpty()) return
        val uris = selectedItems.map { it.uri }
        deliveredResult = true
        dismissAnimated { onResult(uris) }
    }

    private fun bindMediaTile(container: FrameLayout, item: MediaItem, itemIndex: Int) {
        val density = hostActivity.resources.displayMetrics.density
        container.removeAllViews()
        container.setBackgroundColor(0x22888888)
        container.tag = item.id

        val imageView = ImageView(hostActivity).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setOnClickListener { onThumbnailClicked(item, itemIndex) }
        }
        container.addView(imageView)

        repository.loadThumbnail(item.uri, (cellSizePx * 1.5f).roundToInt(), item.isVideo) { bmp ->
            mainHandler.post {
                if (container.tag == item.id && bmp != null) {
                    imageView.setImageBitmap(bmp)
                }
            }
        }

        if (item.isVideo) {
            val durView = TextView(hostActivity).apply {
                text = MediaStoreRepository.formatDuration(item.durationMs)
                textSize = 11f
                setTextColor(Color.WHITE)
                setPadding((6 * density).roundToInt(), (2 * density).roundToInt(), (6 * density).roundToInt(), (2 * density).roundToInt())
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = 6 * density
                    setColor(0x88000000.toInt())
                }
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM or Gravity.START
                ).apply {
                    marginStart = (5 * density).roundToInt()
                    bottomMargin = (5 * density).roundToInt()
                }
            }
            container.addView(durView)
        }

        val selIdx = selectedItems.indexOfFirst { it.id == item.id }
        val hitSize = (38 * density).roundToInt()
        val badgeSize = (24 * density).roundToInt()
        val badgeHitArea = FrameLayout(hostActivity).apply {
            layoutParams = FrameLayout.LayoutParams(hitSize, hitSize, Gravity.TOP or Gravity.END)
            setOnClickListener { onBadgeClicked(item) }
        }
        val badgeCircle = FrameLayout(hostActivity).apply {
            layoutParams = FrameLayout.LayoutParams(badgeSize, badgeSize, Gravity.TOP or Gravity.END).apply {
                topMargin = (6 * density).roundToInt()
                marginEnd = (6 * density).roundToInt()
            }
            if (selIdx >= 0) {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(config.theme.primaryColor)
                }
                if (config.multiple) {
                    addView(TextView(hostActivity).apply {
                        text = "${selIdx + 1}"
                        textSize = 12f
                        typeface = Typeface.DEFAULT_BOLD
                        setTextColor(config.theme.onPrimaryColor)
                        gravity = Gravity.CENTER
                        layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    })
                } else {
                    addView(ImageView(hostActivity).apply {
                        setImageResource(R.drawable.xh_ic_check)
                        setColorFilter(config.theme.onPrimaryColor, PorterDuff.Mode.SRC_IN)
                        val iconPx = (15 * density).roundToInt()
                        layoutParams = FrameLayout.LayoutParams(iconPx, iconPx, Gravity.CENTER)
                    })
                }
            } else {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(config.theme.unselectedBadgeFillColor)
                    setStroke((1.8f * density).roundToInt(), config.theme.unselectedBadgeBorderColor)
                }
            }
        }
        badgeHitArea.addView(badgeCircle)
        container.addView(badgeHitArea)
    }

    private inner class MediaGridAdapter : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

        private val typeHero = 0
        private val typeCell = 1

        override fun getItemViewType(position: Int): Int {
            return if (hasHeroCameraHeader() && position == 0) typeHero else typeCell
        }

        override fun getItemCount(): Int {
            return if (hasHeroCameraHeader()) {
                1 + (currentItems.size - heroRightItemCount()).coerceAtLeast(0)
            } else {
                currentItems.size
            }
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            return if (viewType == typeHero) {
                val heroHeight = cellSizePx * 2 + spacingPx
                val row = LinearLayout(hostActivity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    layoutParams = RecyclerView.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        heroHeight + spacingPx
                    )
                    setPadding(0, 0, 0, spacingPx)
                }
                HeroViewHolder(row)
            } else {
                val cell = FrameLayout(hostActivity).apply {
                    layoutParams = RecyclerView.LayoutParams(cellSizePx, cellSizePx).apply {
                        bottomMargin = spacingPx
                    }
                }
                CellViewHolder(cell)
            }
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            if (holder is HeroViewHolder) {
                holder.bind()
            } else if (holder is CellViewHolder) {
                val itemIdx = adapterPositionToItemIndex(position)
                val item = currentItems.getOrNull(itemIdx) ?: return
                val col = (if (hasHeroCameraHeader()) position - 1 else position) % config.crossAxisCount
                val lp = holder.container.layoutParams as RecyclerView.LayoutParams
                lp.marginEnd = if (col < config.crossAxisCount - 1) spacingPx else 0
                holder.container.layoutParams = lp
                bindMediaTile(holder.container, item, itemIdx)
            }
        }
    }

    private inner class HeroViewHolder(private val root: LinearLayout) :
        RecyclerView.ViewHolder(root) {

        private val cameraTile = CameraPreviewTileView(hostActivity).apply {
            setCameraLabel(config.strings.cameraLabel)
        }
        private val rightColumn = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
        }

        init {
            val heroHeight = cellSizePx * 2 + spacingPx
            cameraTile.layoutParams = LinearLayout.LayoutParams(cellSizePx, heroHeight).apply {
                marginEnd = spacingPx
            }
            cameraTile.setOnClickListener {
                deliveredResult = true
                dismissAnimated { onLaunchCamera() }
            }
            root.addView(cameraTile)

            rightColumn.layoutParams = LinearLayout.LayoutParams(0, heroHeight, 1f)
            root.addView(rightColumn)
            activeCameraTile = cameraTile
            cameraTile.startPreview()
        }

        fun bind() {
            rightColumn.removeAllViews()
            val rightCols = config.crossAxisCount - 1
            for (r in 0 until 2) {
                val rowLayout = LinearLayout(hostActivity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        cellSizePx
                    ).apply {
                        if (r == 0) bottomMargin = spacingPx
                    }
                }
                for (c in 0 until rightCols) {
                    val idx = r * rightCols + c
                    val slot = FrameLayout(hostActivity).apply {
                        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                            if (c < rightCols - 1) marginEnd = spacingPx
                        }
                    }
                    val item = currentItems.getOrNull(idx)
                    if (item != null) {
                        bindMediaTile(slot, item, idx)
                    }
                    rowLayout.addView(slot)
                }
                rightColumn.addView(rowLayout)
            }
        }
    }

    private inner class CellViewHolder(val container: FrameLayout) :
        RecyclerView.ViewHolder(container)
}
