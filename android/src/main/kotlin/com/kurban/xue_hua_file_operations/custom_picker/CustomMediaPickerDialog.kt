package com.kurban.xue_hua_file_operations.custom_picker

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.PorterDuff
import android.graphics.Rect
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
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
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
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Customizable native sheet-style media picker for Android.
 * Uses a unified nested-scroll gesture container so dragging anywhere on the sheet
 * or grid smoothly tracks the finger 1:1 between half-screen, full-screen, and
 * dismiss states with velocity-aware snapping and zero layout jitter.
 *
 * Android 端可自定义样式的原生抽屉式媒体选择器。
 * 采用统一嵌套滑动手势容器：支持在面板或网格任意位置跟手 1:1 上拉展开至全屏、
 * 全屏滚到顶部后无缝下拉回半屏或继续下拉关闭，结合速度感知吸附动画且全程无布局抖动。
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
    private var currentSheetOffsetY = 0f
    private var currentCornerRadiusPx = 0f
    private var collapsedTopOffsetPx = 0f
    private var screenHeightPx = 0
    private var screenWidthPx = 0
    private var cellSizePx = 0
    private var spacingPx = 0
    private var statusBarHeightPx = 0
    private var navBarHeightPx = 0

    private lateinit var scrimView: View
    private lateinit var sheetContainer: SheetGestureContainer
    private lateinit var dragHandlePill: View
    private lateinit var limitedBanner: LinearLayout
    private lateinit var topBarContainer: FrameLayout
    private lateinit var albumTitleText: TextView
    private lateinit var recyclerView: RecyclerView
    private lateinit var emptyStateContainer: LinearLayout
    private lateinit var bottomConfirmBar: FrameLayout
    private lateinit var confirmButton: TextView
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
        collapsedTopOffsetPx = screenHeightPx * 0.42f

        val root = FrameLayout(hostActivity).apply {
            clipChildren = false
            clipToPadding = false
        }

        // Dimmed backdrop scrim / 半透明背景遮罩
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

        // Full-height gesture-aware sheet container with GPU rounded-top clipping
        // 全高嵌套手势抽屉容器，采用 OutlineProvider 实现高性能 GPU 顶部圆角裁剪
        sheetContainer = SheetGestureContainer(hostActivity).apply {
            setBackgroundColor(config.theme.backgroundColor)
            clipToOutline = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    val r = currentCornerRadiusPx
                    outline.setRoundRect(0, 0, view.width, view.height + r.roundToInt(), r)
                }
            }
            isClickable = true
            isFocusable = true
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        root.addView(sheetContainer)

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
            itemAnimator = null
            clipToPadding = false
            overScrollMode = View.OVER_SCROLL_NEVER
            setPadding(0, dp(24), 0, dp(88))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        attachScrollListeners()
        sheetContainer.addView(recyclerView)

        // Empty / Permission-denied state / 空态或无权限状态视图
        emptyStateContainer = buildEmptyOrDeniedView(density)
        sheetContainer.addView(emptyStateContainer)

        // Top drag handle pill overlaid cleanly above the grid (no layout reflow during drag)
        // 顶部居中拖拽指示条（悬浮叠加，拖拽过程零布局重排）
        dragHandlePill = View(hostActivity).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 3 * density
                setColor(config.theme.handleColor)
            }
            layoutParams = FrameLayout.LayoutParams(
                (40 * density).roundToInt(),
                (5 * density).roundToInt(),
                Gravity.TOP or Gravity.CENTER_HORIZONTAL
            ).apply {
                topMargin = (10 * density).roundToInt()
            }
        }
        sheetContainer.addView(dragHandlePill)

        // Optional limited-access banner (Android 14+ partial photo access)
        // Android 14+ 部分照片授权提示条
        limitedBanner = buildLimitedAccessBanner(density)
        limitedBanner.visibility = if (isLimitedAccess && !isPermissionDenied) View.VISIBLE else View.GONE
        sheetContainer.addView(limitedBanner)

        // Floating pill top bar (fades in smoothly as sheet approaches fullscreen)
        // 顶部悬浮胶囊操作栏（半屏隐藏，随上拉展开平滑渐显）
        topBarContainer = buildFloatingTopBar(density)
        sheetContainer.addView(topBarContainer)

        // Fast-scroll thumb & floating date bubble / 右侧快滑手柄与日期浮窗
        buildFastScrollerOverlays(sheetContainer, density)

        // Mount bottom confirmation bar on root so it stays visible in BOTH half-screen and full-screen.
        // 将底部确认栏挂载在 root 上，保证半屏与全屏状态下多选确认按钮均始终可见。
        bottomConfirmBar = buildBottomConfirmBar(density)
        root.addView(bottomConfirmBar)

        // Apply real system status bar & navigation bar insets
        // 监听并适配系统状态栏与底部导航栏安全区
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            statusBarHeightPx = bars.top
            navBarHeightPx = bars.bottom
            applyStaticInsets()
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
        applySheetOffset(screenHeightPx.toFloat())
        root.post {
            val targetOffset = if (config.initialExpanded) 0f else collapsedTopOffsetPx
            animateSheetToOffset(targetOffset, durationMs = 300)
        }

        if (isPermissionDenied) {
            showDeniedState()
        } else {
            loadMediaAsync()
        }
    }

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
            applyStaticInsets()
            applySheetOffset(currentSheetOffsetY)
            loadMediaAsync()
        } else if (!denied && limited != isLimitedAccess) {
            isLimitedAccess = limited
            limitedBanner.visibility = if (limited) View.VISIBLE else View.GONE
            applyStaticInsets()
            loadMediaAsync()
        }
    }

    fun reloadMedia() {
        if (!isShowing) return
        val (denied, limited) = onRecheckPermission()
        isPermissionDenied = denied
        isLimitedAccess = limited
        limitedBanner.visibility = if (limited && !denied) View.VISIBLE else View.GONE
        applyStaticInsets()
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

    private fun applyStaticInsets() {
        topBarContainer.setPadding(dp(14), statusBarHeightPx + dp(10), dp(14), dp(14))
        val bannerLp = limitedBanner.layoutParams as FrameLayout.LayoutParams
        bannerLp.topMargin = statusBarHeightPx + dp(62)
        limitedBanner.layoutParams = bannerLp

        val topPad = if (limitedBanner.visibility == View.VISIBLE) dp(64) else dp(24)
        recyclerView.setPadding(0, topPad, 0, navBarHeightPx + dp(92))
        bottomConfirmBar.setPadding(dp(16), dp(12), dp(16), dp(16) + navBarHeightPx)
    }

    /**
     * Applies all GPU-composited visual properties for a given vertical sheet
     * offset (`0f` = fullscreen, `collapsedTopOffsetPx` = half-screen,
     * `screenHeightPx` = dismissed). Zero layout passes or padding mutations!
     * 根据抽屉垂直偏移量实时更新纯 GPU 视觉属性（圆角、遮罩、拖拽条、悬浮顶栏），
     * 全程不触发布局重排，确保 60/120fps 顺滑跟手。
     */
    private fun applySheetOffset(offsetY: Float) {
        val clamped = offsetY.coerceIn(0f, screenHeightPx.toFloat())
        currentSheetOffsetY = clamped
        sheetContainer.translationY = clamped

        val density = hostActivity.resources.displayMetrics.density
        val half = collapsedTopOffsetPx.coerceAtLeast(1f)

        // Expand progress: 0f at half-screen -> 1f at fullscreen
        // 展开进度：0f（半屏）-> 1f（全屏）
        val expandProgress = (1f - (clamped / half)).coerceIn(0f, 1f)

        // Dismiss fade: 1f at half-screen or higher -> 0f at screen bottom
        // 收起遮罩透明度：半屏及以上为 1f，继续下拉至底部平滑淡出至 0f
        val scrimFraction = if (clamped <= half) {
            1f
        } else {
            val dismissRange = (screenHeightPx - half).coerceAtLeast(1f)
            (1f - ((clamped - half) / dismissRange)).coerceIn(0f, 1f)
        }
        scrimView.alpha = scrimFraction
        if (bottomConfirmBar.visibility == View.VISIBLE && selectedItems.isNotEmpty()) {
            bottomConfirmBar.alpha = scrimFraction
        }

        // Smooth top corner radius via GPU OutlineProvider
        // 通过 OutlineProvider 平滑插值顶部圆角（半屏圆角 -> 全屏直角）
        val newRadius = config.theme.sheetCornerRadiusDp * density * (1f - expandProgress)
        if (abs(newRadius - currentCornerRadiusPx) > 0.25f) {
            currentCornerRadiusPx = newRadius
            sheetContainer.invalidateOutline()
        }

        // Drag handle fades out smoothly as fullscreen is reached
        // 展开至全屏时平滑淡出顶部拖拽指示条
        dragHandlePill.alpha = (1f - expandProgress * 1.8f).coerceIn(0f, 1f)

        // Floating top bar smoothly fades & slides in as sheet expands past 35%
        // 顶部悬浮胶囊栏在半屏隐藏，上拉展开超过 35% 后平滑淡入并微幅下移就位
        val topBarAlpha = if (isPermissionDenied) {
            1f
        } else {
            ((expandProgress - 0.35f) / 0.65f).coerceIn(0f, 1f)
        }
        topBarContainer.alpha = topBarAlpha
        topBarContainer.visibility = if (topBarAlpha > 0.02f) View.VISIBLE else View.INVISIBLE
        topBarContainer.translationY = -(1f - topBarAlpha) * (14 * density)
    }

    private fun animateSheetToOffset(
        targetOffsetY: Float,
        durationMs: Long = 260,
        onEnd: (() -> Unit)? = null,
    ) {
        sheetAnimator?.cancel()
        val startOffset = currentSheetOffsetY
        val target = targetOffsetY.coerceIn(0f, screenHeightPx.toFloat())
        if (abs(target - startOffset) < 1f) {
            applySheetOffset(target)
            onEnd?.invoke()
            return
        }
        sheetAnimator = ValueAnimator.ofFloat(startOffset, target).apply {
            duration = durationMs
            interpolator = sheetInterpolator
            addUpdateListener { anim ->
                applySheetOffset(anim.animatedValue as Float)
            }
            if (onEnd != null) {
                addListener(object : AnimatorListenerAdapter() {
                    private var cancelled = false
                    override fun onAnimationCancel(animation: Animator) {
                        cancelled = true
                    }

                    override fun onAnimationEnd(animation: Animator) {
                        if (!cancelled) onEnd()
                    }
                })
            }
            start()
        }
    }

    private fun dismissAnimated(afterDismiss: (() -> Unit)? = null) {
        if (isDismissing) return
        isDismissing = true
        activePopup?.dismiss()
        animateSheetToOffset(screenHeightPx.toFloat(), durationMs = 230) {
            super.dismiss()
            afterDismiss?.invoke()
        }
    }

    /**
     * Unified nested-scroll gesture container that coordinates vertical sheet
     * dragging with [RecyclerView] scrolling seamlessly in both directions.
     * 统一嵌套滑动手势容器：无缝协调抽屉面板拖拽与 [RecyclerView] 列表滚动，
     * 支持半屏任意位置上拉全屏、全屏到顶后顺滑下拉回半屏或继续下拉关闭。
     */
    private inner class SheetGestureContainer(context: Context) : FrameLayout(context) {
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private val density = context.resources.displayMetrics.density
        private var velocityTracker: VelocityTracker? = null

        private var downX = 0f
        private var downY = 0f
        private var lastRawY = 0f
        private var isDraggingSheet = false
        private var ignoreGesture = false
        private var startedInFullscreen = false

        private fun isPointInView(view: View, rawX: Float, rawY: Float): Boolean {
            if (view.visibility != View.VISIBLE) return false
            val loc = IntArray(2)
            view.getLocationOnScreen(loc)
            val rect = Rect(loc[0], loc[1], loc[0] + view.width, loc[1] + view.height)
            return rect.contains(rawX.roundToInt(), rawY.roundToInt())
        }

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
            if (isDismissing) return true
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    isDraggingSheet = false
                    ignoreGesture = isPointInView(fastScrollThumb, ev.rawX, ev.rawY) ||
                            isPointInView(bottomConfirmBar, ev.rawX, ev.rawY)
                    if (!ignoreGesture) {
                        // Catch sheet smoothly if grabbed mid-animation / 动画中途接手不跳变
                        sheetAnimator?.cancel()
                        downX = ev.rawX
                        downY = ev.rawY
                        lastRawY = ev.rawY
                        startedInFullscreen = currentSheetOffsetY <= 2f
                        velocityTracker?.recycle()
                        velocityTracker = VelocityTracker.obtain().apply { addMovement(ev) }
                    }
                    return false
                }

                MotionEvent.ACTION_MOVE -> {
                    if (ignoreGesture) return false
                    velocityTracker?.addMovement(ev)
                    val dx = ev.rawX - downX
                    val dy = ev.rawY - downY
                    if (abs(dy) > touchSlop && abs(dy) > abs(dx)) {
                        val isHalfOrMid = currentSheetOffsetY > 2f
                        val isGridAtTop = !recyclerView.canScrollVertically(-1)
                        val isInTopArea = (downY - currentSheetOffsetY) < (statusBarHeightPx + dp(72))
                        // Intercept in half-sheet for any vertical drag, or in fullscreen
                        // when pulling downward at the top of the grid (or top bar area).
                        // 半屏态拦截任意上下滑动；全屏态当列表已到顶或从顶栏下滑时无缝接管下拉。
                        if (isHalfOrMid || (dy > 0f && (isGridAtTop || isInTopArea))) {
                            activePopup?.dismiss()
                            isDraggingSheet = true
                            lastRawY = ev.rawY
                            return true
                        }
                    }
                    return false
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    velocityTracker?.recycle()
                    velocityTracker = null
                    isDraggingSheet = false
                    return false
                }
            }
            return super.onInterceptTouchEvent(ev)
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(ev: MotionEvent): Boolean {
            if (isDismissing) return true
            velocityTracker?.addMovement(ev)
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> return true

                MotionEvent.ACTION_MOVE -> {
                    val deltaY = ev.rawY - lastRawY
                    lastRawY = ev.rawY
                    if (!isDraggingSheet) {
                        val dy = ev.rawY - downY
                        if (abs(dy) > touchSlop) {
                            isDraggingSheet = true
                        } else {
                            return true
                        }
                    }
                    val nextOffset = (currentSheetOffsetY + deltaY).coerceAtLeast(0f)
                    applySheetOffset(nextOffset)
                    return true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (isDraggingSheet) {
                        velocityTracker?.computeCurrentVelocity(1000)
                        val velocityDpPerSec = (velocityTracker?.yVelocity ?: 0f) / density
                        settleSheetAfterDrag(velocityDpPerSec)
                    }
                    velocityTracker?.recycle()
                    velocityTracker = null
                    isDraggingSheet = false
                    return true
                }
            }
            return super.onTouchEvent(ev)
        }

        private fun settleSheetAfterDrag(velocityDpPerSec: Float) {
            val offset = currentSheetOffsetY
            val half = collapsedTopOffsetPx
            when {
                // Fast upward fling -> expand smoothly to fullscreen / 快速上滑 -> 吸附全屏
                velocityDpPerSec < -550f -> animateSheetToOffset(0f)

                // Very fast downward fling -> dismiss directly / 极速下滑 -> 直接关闭
                velocityDpPerSec > 1800f -> dismissAnimated()

                // Moderate downward fling -> fullscreen snaps to half; half dismisses
                // 中速下滑 -> 全屏态回到半屏，半屏态则关闭
                velocityDpPerSec > 550f -> {
                    if (startedInFullscreen && offset < half * 1.15f) {
                        animateSheetToOffset(half)
                    } else {
                        dismissAnimated()
                    }
                }

                // Slow release: snap to nearest anchor / 慢速松手按位置吸附最近锚点
                offset < half * 0.5f -> animateSheetToOffset(0f)
                offset <= half + screenHeightPx * 0.17f -> animateSheetToOffset(half)
                else -> dismissAnimated()
            }
        }
    }

    private fun dp(value: Int): Int = (value * hostActivity.resources.displayMetrics.density).roundToInt()

    private fun buildLimitedAccessBanner(density: Float): LinearLayout {
        return LinearLayout(hostActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(config.theme.surfaceColor)
            elevation = 4 * density
            setPadding((16 * density).roundToInt(), (10 * density).roundToInt(), (16 * density).roundToInt(), (10 * density).roundToInt())
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
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
                val range = (rv.computeVerticalScrollRange() - rv.computeVerticalScrollExtent()).coerceAtLeast(1)
                val offset = rv.computeVerticalScrollOffset()
                val fraction = (offset.toFloat() / range.toFloat()).coerceIn(0f, 1f)
                val showThumb = currentItems.size > config.crossAxisCount * 5 && currentSheetOffsetY <= 2f
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
        applySheetOffset(currentSheetOffsetY)

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

    /**
     * Updates ONLY the selection badges on currently visible grid tiles in place,
     * without calling `notifyDataSetChanged()` or recreating ImageViews (zero flash).
     * 仅就地刷新当前可见网格项的选中角标，不调用 `notifyDataSetChanged()` 也不重建图片视图，彻底杜绝闪烁。
     */
    private fun updateVisibleSelectionBadges() {
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i) ?: continue
            when (val holder = recyclerView.getChildViewHolder(child)) {
                is HeroViewHolder -> holder.refreshBadgesOnly()
                is CellViewHolder -> holder.refreshBadgeOnly()
            }
        }
    }

    private fun refreshSelectionUI() {
        updateVisibleSelectionBadges()
        val count = selectedItems.size
        val density = hostActivity.resources.displayMetrics.density
        if (count > 0) {
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

    /**
     * Reusable media thumbnail cell view that keeps its ImageView and badge
     * views allocated across binds so toggling selection never flickers.
     * 可复用媒体缩略图视图：跨绑定复用 ImageView 与角标控件，切换选中态时只更新角标，零闪烁。
     */
    private inner class MediaTileView(context: Context) : FrameLayout(context) {
        private val density = context.resources.displayMetrics.density
        private val imageView = ImageView(context)
        private val durationView = TextView(context)
        private val badgeHitArea = FrameLayout(context)
        private val badgeCircle = FrameLayout(context)
        private val badgeNumber = TextView(context)
        private val badgeCheck = ImageView(context)

        private var boundItem: MediaItem? = null
        private var boundItemIndex: Int = -1

        init {
            setBackgroundColor(0x22888888)
            imageView.apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
                setOnClickListener {
                    val item = boundItem ?: return@setOnClickListener
                    onThumbnailClicked(item, boundItemIndex)
                }
            }
            addView(imageView)

            durationView.apply {
                textSize = 11f
                setTextColor(Color.WHITE)
                setPadding((6 * density).roundToInt(), (2 * density).roundToInt(), (6 * density).roundToInt(), (2 * density).roundToInt())
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = 6 * density
                    setColor(0x88000000.toInt())
                }
                visibility = View.GONE
                layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.START).apply {
                    marginStart = (5 * density).roundToInt()
                    bottomMargin = (5 * density).roundToInt()
                }
            }
            addView(durationView)

            val hitSize = (38 * density).roundToInt()
            val badgeSize = (24 * density).roundToInt()
            badgeHitArea.apply {
                layoutParams = LayoutParams(hitSize, hitSize, Gravity.TOP or Gravity.END)
                setOnClickListener {
                    val item = boundItem ?: return@setOnClickListener
                    onBadgeClicked(item)
                }
            }
            badgeCircle.layoutParams = LayoutParams(badgeSize, badgeSize, Gravity.TOP or Gravity.END).apply {
                topMargin = (6 * density).roundToInt()
                marginEnd = (6 * density).roundToInt()
            }
            badgeNumber.apply {
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(config.theme.onPrimaryColor)
                gravity = Gravity.CENTER
                visibility = View.GONE
                layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            }
            badgeCheck.apply {
                setImageResource(R.drawable.xh_ic_check)
                setColorFilter(config.theme.onPrimaryColor, PorterDuff.Mode.SRC_IN)
                val iconPx = (15 * density).roundToInt()
                visibility = View.GONE
                layoutParams = LayoutParams(iconPx, iconPx, Gravity.CENTER)
            }
            badgeCircle.addView(badgeNumber)
            badgeCircle.addView(badgeCheck)
            badgeHitArea.addView(badgeCircle)
            addView(badgeHitArea)
        }

        fun bind(item: MediaItem?, itemIndex: Int) {
            if (item == null) {
                boundItem = null
                boundItemIndex = -1
                visibility = View.INVISIBLE
                return
            }
            visibility = View.VISIBLE
            val itemChanged = boundItem?.id != item.id
            boundItem = item
            boundItemIndex = itemIndex

            if (itemChanged) {
                imageView.setImageBitmap(null)
                val targetId = item.id
                repository.loadThumbnail(item.uri, (cellSizePx * 1.5f).roundToInt(), item.isVideo) { bmp ->
                    mainHandler.post {
                        if (boundItem?.id == targetId && bmp != null) {
                            imageView.setImageBitmap(bmp)
                        }
                    }
                }
                if (item.isVideo) {
                    durationView.text = MediaStoreRepository.formatDuration(item.durationMs)
                    durationView.visibility = View.VISIBLE
                } else {
                    durationView.visibility = View.GONE
                }
            }
            refreshBadgeOnly()
        }

        fun refreshBadgeOnly() {
            val item = boundItem ?: return
            val selIdx = selectedItems.indexOfFirst { it.id == item.id }
            if (selIdx >= 0) {
                badgeCircle.background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(config.theme.primaryColor)
                }
                if (config.multiple) {
                    badgeCheck.visibility = View.GONE
                    badgeNumber.visibility = View.VISIBLE
                    badgeNumber.text = "${selIdx + 1}"
                } else {
                    badgeNumber.visibility = View.GONE
                    badgeCheck.visibility = View.VISIBLE
                }
            } else {
                badgeNumber.visibility = View.GONE
                badgeCheck.visibility = View.GONE
                badgeCircle.background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(config.theme.unselectedBadgeFillColor)
                    setStroke((1.8f * density).roundToInt(), config.theme.unselectedBadgeBorderColor)
                }
            }
        }
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
                val tile = MediaTileView(hostActivity).apply {
                    layoutParams = RecyclerView.LayoutParams(cellSizePx, cellSizePx).apply {
                        bottomMargin = spacingPx
                    }
                }
                CellViewHolder(tile)
            }
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            if (holder is HeroViewHolder) {
                holder.bind()
            } else if (holder is CellViewHolder) {
                val itemIdx = adapterPositionToItemIndex(position)
                val item = currentItems.getOrNull(itemIdx)
                val col = (if (hasHeroCameraHeader()) position - 1 else position) % config.crossAxisCount
                val lp = holder.tileView.layoutParams as RecyclerView.LayoutParams
                lp.marginEnd = if (col < config.crossAxisCount - 1) spacingPx else 0
                holder.tileView.layoutParams = lp
                holder.tileView.bind(item, itemIdx)
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
        private val rightTiles = ArrayList<MediaTileView>()

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
                    val tile = MediaTileView(hostActivity).apply {
                        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                            if (c < rightCols - 1) marginEnd = spacingPx
                        }
                    }
                    rightTiles.add(tile)
                    rowLayout.addView(tile)
                }
                rightColumn.addView(rowLayout)
            }
            root.addView(rightColumn)
            activeCameraTile = cameraTile
            cameraTile.startPreview()
        }

        fun bind() {
            for (idx in rightTiles.indices) {
                rightTiles[idx].bind(currentItems.getOrNull(idx), idx)
            }
        }

        fun refreshBadgesOnly() {
            for (tile in rightTiles) {
                tile.refreshBadgeOnly()
            }
        }
    }

    private inner class CellViewHolder(val tileView: MediaTileView) :
        RecyclerView.ViewHolder(tileView) {
        fun refreshBadgeOnly() = tileView.refreshBadgeOnly()
    }
}
