package com.kurban.xue_hua_file_operations.custom_picker

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlin.concurrent.thread
import kotlin.math.roundToInt
import androidx.core.graphics.drawable.toDrawable

/**
 * Customizable native sheet-style media picker for Android.
 * Features an expandable half-to-fullscreen sheet container, floating pill top bar,
 * album dropdown popover, overflow menu ("Open in other app..."), optional 1x2 live
 * camera preview tile, right-edge fast scroller with floating month-year bubble,
 * full-screen preview dialog, and bottom confirmation bar.
 *
 * Android 端可自定义样式的原生抽屉式媒体选择器。
 * 支持半屏上拉展开至全屏、顶部悬浮胶囊栏、相册下拉浮窗、更多菜单（使用其它应用打开…）、
 * 可配置的左上角 1×2 实时相机预览格、右侧快速滚动与日期浮窗、全屏预览页及底部确认栏。
 */
class CustomMediaPickerDialog(
    private val hostActivity: Activity,
    private val config: CustomMediaPickerConfig,
    private val isLimitedAccess: Boolean,
    private val isPermissionDenied: Boolean,
    private val onResult: (List<Uri>?) -> Unit,
    private val onOpenInOtherApp: () -> Unit,
    private val onLaunchCamera: () -> Unit,
    private val onManageLimitedPermission: () -> Unit,
    private val onOpenAppSettings: () -> Unit,
) : Dialog(hostActivity, android.R.style.Theme_Translucent_NoTitleBar) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val repository = MediaStoreRepository(hostActivity)

    private var albums: List<MediaAlbum> = emptyList()
    private var itemsByAlbum: Map<String, List<MediaItem>> = emptyMap()
    private var currentAlbumId: String = MediaAlbum.ID_ALL_MEDIA
    private var currentItems: List<MediaItem> = emptyList()
    private val selectedItems = ArrayList<MediaItem>()

    private var deliveredResult = false
    private var isExpanded = config.initialExpanded
    private var collapsedTopOffsetPx = 0
    private var screenHeightPx = 0
    private var screenWidthPx = 0
    private var cellSizePx = 0
    private var spacingPx = 0

    private lateinit var sheetContainer: FrameLayout
    private lateinit var topBarContainer: FrameLayout
    private lateinit var albumTitleButton: TextView
    private lateinit var recyclerView: RecyclerView
    private lateinit var emptyStateContainer: LinearLayout
    private lateinit var bottomConfirmBar: FrameLayout
    private lateinit var confirmButton: TextView
    private lateinit var selectedHintView: TextView
    private lateinit var fastScrollThumb: TextView
    private lateinit var dateBubbleView: TextView
    private var activeCameraTile: CameraPreviewTileView? = null
    private var activePopup: PopupWindow? = null

    private val gridAdapter = MediaGridAdapter()
    private val hideDateBubbleRunnable = Runnable {
        dateBubbleView.animate().alpha(0f).setDuration(180).withEndAction {
            dateBubbleView.visibility = View.GONE
        }.start()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window?.apply {
            setBackgroundDrawable(Color.TRANSPARENT.toDrawable())
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        }

        val metrics = hostActivity.resources.displayMetrics
        val density = metrics.density
        screenHeightPx = metrics.heightPixels
        screenWidthPx = metrics.widthPixels
        spacingPx = (config.theme.gridSpacingDp * density).roundToInt()
        cellSizePx =
            ((screenWidthPx - spacingPx * (config.crossAxisCount - 1)) / config.crossAxisCount)
                .coerceAtLeast(1)
        collapsedTopOffsetPx = (screenHeightPx * 0.38f).roundToInt()

        val root = FrameLayout(hostActivity).apply {
            setBackgroundColor(config.theme.scrimColor)
            setOnClickListener { dismiss() }
        }

        sheetContainer = FrameLayout(hostActivity).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            // Intercept clicks so tapping inside sheet does not dismiss via scrim.
            // 拦截点击事件，避免点击面板内部时触发背景遮罩关闭。
            isClickable = true
            isFocusable = true
        }
        applySheetBackground(expanded = isExpanded)
        sheetContainer.translationY = if (isExpanded) 0f else collapsedTopOffsetPx.toFloat()
        root.addView(sheetContainer)

        val contentColumn = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        sheetContainer.addView(contentColumn)

        // Drag handle area (visible especially in half-sheet mode)
        // 顶部拖拽手柄区域（支持上下拖动切换半屏/全屏或下滑关闭）
        val handleContainer = buildDragHandleArea(density)
        contentColumn.addView(handleContainer)

        // Optional limited-access banner (Android 14+ partial photo access)
        // 可选的部分照片授权顶部提示条（Android 14+）
        if (isLimitedAccess && !isPermissionDenied) {
            contentColumn.addView(buildLimitedAccessBanner(density))
        }

        // Media grid container + overlays / 媒体网格与悬浮控件容器
        val gridWrapper = FrameLayout(hostActivity).apply {
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
            setPadding(0, dp(64), 0, dp(88))
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

        // Floating pill top bar (back, album pill, overflow menu)
        // 顶部悬浮胶囊操作栏（返回按钮、相册切换胶囊、更多菜单按钮）
        topBarContainer = buildFloatingTopBar(density)
        gridWrapper.addView(topBarContainer)

        // Fast-scroll thumb & floating date bubble on right edge
        // 右侧快速滚动手柄与月份年份日期浮窗
        buildFastScrollerOverlays(gridWrapper, density)

        // Bottom confirmation bar / 底部选中确认栏
        bottomConfirmBar = buildBottomConfirmBar(density)
        gridWrapper.addView(bottomConfirmBar)

        setContentView(root)
        setOnDismissListener {
            activePopup?.dismiss()
            activeCameraTile?.stopPreview()
            repository.release()
            if (!deliveredResult) {
                deliveredResult = true
                onResult(null)
            }
        }

        if (isPermissionDenied) {
            showDeniedState()
        } else {
            loadMediaAsync()
        }
    }

    /**
     * Reloads media items after the user updates limited photo permissions.
     * 用户在 Android 14+ 部分授权管理后重新加载媒体列表。
     */
    fun reloadMedia() {
        if (!isShowing) return
        loadMediaAsync()
    }

    private fun dp(value: Int): Int =
        (value * hostActivity.resources.displayMetrics.density).roundToInt()

    private fun applySheetBackground(expanded: Boolean) {
        val radius =
            if (expanded) 0f else config.theme.sheetCornerRadiusDp * hostActivity.resources.displayMetrics.density
        sheetContainer.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(config.theme.backgroundColor)
            cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun buildDragHandleArea(density: Float): FrameLayout {
        val container = FrameLayout(hostActivity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (28 * density).roundToInt()
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
                    downRawY = event.rawY
                    startTranslationY = sheetContainer.translationY
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val delta = event.rawY - downRawY
                    val target = (startTranslationY + delta).coerceAtLeast(0f)
                    sheetContainer.translationY = target
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val currentY = sheetContainer.translationY
                    when {
                        currentY < collapsedTopOffsetPx * 0.55f -> animateSheetState(expanded = true)
                        currentY > collapsedTopOffsetPx + screenHeightPx * 0.18f -> dismiss()
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
        applySheetBackground(expanded)
        val targetY = if (expanded) 0f else collapsedTopOffsetPx.toFloat()
        sheetContainer.animate().translationY(targetY).setDuration(220).start()
    }

    private fun buildLimitedAccessBanner(density: Float): LinearLayout {
        return LinearLayout(hostActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(config.theme.surfaceColor)
            setPadding(
                (16 * density).roundToInt(),
                (10 * density).roundToInt(),
                (16 * density).roundToInt(),
                (10 * density).roundToInt()
            )
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
                setPadding(
                    (12 * density).roundToInt(),
                    (4 * density).roundToInt(),
                    0,
                    (4 * density).roundToInt()
                )
                setOnClickListener { onManageLimitedPermission() }
            })
        }
    }

    @SuppressLint("SetTextI18n")
    private fun buildFloatingTopBar(density: Float): FrameLayout {
        val bar = FrameLayout(hostActivity).apply {
            setPadding(
                (14 * density).roundToInt(),
                (8 * density).roundToInt(),
                (14 * density).roundToInt(),
                (8 * density).roundToInt()
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val btnSize = (42 * density).roundToInt()
        val elevationPx = 6 * density

        // Back / close circular button / 左侧圆形返回按钮
        val backBtn = TextView(hostActivity).apply {
            text = "←"
            textSize = 20f
            setTextColor(config.theme.iconColor)
            gravity = Gravity.CENTER
            elevation = elevationPx
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(config.theme.surfaceColor)
            }
            layoutParams =
                FrameLayout.LayoutParams(btnSize, btnSize, Gravity.START or Gravity.CENTER_VERTICAL)
            setOnClickListener { dismiss() }
        }
        bar.addView(backBtn)

        // Center album dropdown pill / 居中相册切换胶囊
        albumTitleButton = TextView(hostActivity).apply {
            text = "${config.strings.galleryTitle} ▾"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.textColor)
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            elevation = elevationPx
            setPadding(
                (18 * density).roundToInt(),
                (9 * density).roundToInt(),
                (18 * density).roundToInt(),
                (9 * density).roundToInt()
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 22 * density
                setColor(config.theme.surfaceColor)
            }
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
        bar.addView(albumTitleButton)

        // Right overflow button (⋮) / 右侧更多操作按钮
        if (config.allowOpenInOtherApp) {
            val moreBtn = TextView(hostActivity).apply {
                text = "⋮"
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(config.theme.iconColor)
                gravity = Gravity.CENTER
                elevation = elevationPx
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(config.theme.surfaceColor)
                }
                layoutParams = FrameLayout.LayoutParams(
                    btnSize,
                    btnSize,
                    Gravity.END or Gravity.CENTER_VERTICAL
                )
                setOnClickListener { showOverflowMenu(this) }
            }
            bar.addView(moreBtn)
        }

        return bar
    }

    @SuppressLint("SetTextI18n")
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
                typeface =
                    if (album.id == currentAlbumId) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
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
                ViewGroup.LayoutParams.WRAP_CONTENT
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
            setBackgroundDrawable(Color.TRANSPARENT.toDrawable())
        }
        // Constrain height when many albums exist / 相册较多时限制弹窗最大高度
        scrollView.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            minOf((albums.size * 58 * density).roundToInt(), maxHeight)
        )
        activePopup = popup
        popup.showAsDropDown(
            anchor,
            -(screenWidthPx * 0.14f).roundToInt(),
            (6 * density).roundToInt()
        )
    }

    @SuppressLint("SetTextI18n")
    private fun showOverflowMenu(anchor: View) {
        activePopup?.dismiss()
        val density = hostActivity.resources.displayMetrics.density

        val card = LinearLayout(hostActivity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                (16 * density).roundToInt(),
                (10 * density).roundToInt(),
                (16 * density).roundToInt(),
                (10 * density).roundToInt()
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 16 * density
                setColor(config.theme.surfaceColor)
            }
            elevation = 12 * density
        }

        val itemRow = TextView(hostActivity).apply {
            text = "↗  ${config.strings.openInOtherApp}"
            textSize = 15f
            setTextColor(config.theme.textColor)
            setPadding(
                (4 * density).roundToInt(),
                (10 * density).roundToInt(),
                (4 * density).roundToInt(),
                (10 * density).roundToInt()
            )
            setOnClickListener {
                activePopup?.dismiss()
                deliveredResult = true
                dismiss()
                onOpenInOtherApp()
            }
        }
        card.addView(itemRow)

        val popupWidth = (screenWidthPx * 0.60f).roundToInt()
        val popup = PopupWindow(card, popupWidth, ViewGroup.LayoutParams.WRAP_CONTENT, true).apply {
            isOutsideTouchable = true
            elevation = 16 * density
            setBackgroundDrawable(Color.TRANSPARENT.toDrawable())
        }
        activePopup = popup
        popup.showAsDropDown(anchor, -(popupWidth - anchor.width), (6 * density).roundToInt())
    }

    @SuppressLint("ClickableViewAccessibility", "SetTextI18n")
    private fun buildFastScrollerOverlays(parent: FrameLayout, density: Float) {
        // Floating date bubble / 快速滚动月份年份浮窗
        dateBubbleView = TextView(hostActivity).apply {
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.dateBubbleTextColor)
            setPadding(
                (14 * density).roundToInt(),
                (8 * density).roundToInt(),
                (14 * density).roundToInt(),
                (8 * density).roundToInt()
            )
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

        // Draggable fast-scroll thumb (▲▼) / 右侧可拖拽快速滚动手柄
        val thumbSize = (38 * density).roundToInt()
        fastScrollThumb = TextView(hostActivity).apply {
            text = "▲\n▼"
            textSize = 9f
            setLineSpacing(0f, 0.85f)
            setTextColor(config.theme.iconColor)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(config.theme.surfaceColor)
            }
            elevation = 6 * density
            visibility = View.GONE
            layoutParams =
                FrameLayout.LayoutParams(thumbSize, thumbSize, Gravity.TOP or Gravity.END).apply {
                    marginEnd = (6 * density).roundToInt()
                    topMargin = (72 * density).roundToInt()
                }
        }

        fastScrollThumb.setOnTouchListener { _, event ->
            val trackTop = (72 * density)
            val trackBottom = (parent.height - 96 * density).coerceAtLeast(trackTop + 1f)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    val parentLoc = IntArray(2)
                    parent.getLocationOnScreen(parentLoc)
                    val localY = (event.rawY - parentLoc[1]).coerceIn(trackTop, trackBottom)
                    val fraction = ((localY - trackTop) / (trackBottom - trackTop)).coerceIn(0f, 1f)
                    val targetPos =
                        (fraction * (gridAdapter.itemCount - 1).coerceAtLeast(0)).roundToInt()
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
                // Auto-expand half-sheet when scrolling downward into the grid.
                // 向下滚动浏览网格时自动平滑展开至全屏。
                if (!isExpanded && dy > 16) {
                    animateSheetState(expanded = true)
                }
                val range =
                    (rv.computeVerticalScrollRange() - rv.computeVerticalScrollExtent()).coerceAtLeast(
                        1
                    )
                val offset = rv.computeVerticalScrollOffset()
                val fraction = (offset.toFloat() / range.toFloat()).coerceIn(0f, 1f)
                val showThumb = currentItems.size > config.crossAxisCount * 5
                fastScrollThumb.visibility = if (showThumb) View.VISIBLE else View.GONE
                if (showThumb) {
                    updateFastScrollPosition(
                        fraction,
                        showBubble = rv.scrollState != RecyclerView.SCROLL_STATE_IDLE
                    )
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
        val trackTop = 72 * density
        val trackBottom = (parentHeight - 104 * density).coerceAtLeast(trackTop + 1f)
        val y = trackTop + fraction * (trackBottom - trackTop)
        fastScrollThumb.translationY = y - trackTop
        dateBubbleView.translationY = y - trackTop

        val lm = recyclerView.layoutManager as? GridLayoutManager ?: return
        val firstVisible = lm.findFirstVisibleItemPosition().coerceAtLeast(0)
        val itemIndex = adapterPositionToItemIndex(firstVisible).coerceIn(
            0,
            (currentItems.size - 1).coerceAtLeast(0)
        )
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
            setPadding(
                (16 * density).roundToInt(),
                (12 * density).roundToInt(),
                (16 * density).roundToInt(),
                (16 * density).roundToInt()
            )
            visibility = View.GONE
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
            setPadding(
                (22 * density).roundToInt(),
                (10 * density).roundToInt(),
                (22 * density).roundToInt(),
                (10 * density).roundToInt()
            )
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
            setPadding(
                (20 * density).roundToInt(),
                (10 * density).roundToInt(),
                (20 * density).roundToInt(),
                (10 * density).roundToInt()
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 20 * density
                setColor(config.theme.primaryColor)
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = (16 * density).roundToInt()
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
            val (loadedAlbums, loadedMap) = repository.loadMediaAndAlbums(
                config.mediaType,
                config.strings
            )
            mainHandler.post {
                if (!isShowing) return@post
                albums = loadedAlbums
                itemsByAlbum = loadedMap
                val targetAlbum =
                    albums.firstOrNull { it.id == currentAlbumId } ?: albums.firstOrNull()
                if (targetAlbum != null) {
                    selectAlbum(targetAlbum)
                } else {
                    showEmptyState()
                }
            }
        }
    }

    @SuppressLint("SetTextI18n", "NotifyDataSetChanged")
    private fun selectAlbum(album: MediaAlbum) {
        currentAlbumId = album.id
        currentItems = itemsByAlbum[album.id].orEmpty()
        albumTitleButton.text =
            "${if (album.isAllMedia) config.strings.galleryTitle else album.name} ▾"
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

    @SuppressLint("NotifyDataSetChanged", "SetTextI18n")
    private fun refreshSelectionUI() {
        gridAdapter.notifyDataSetChanged()
        val count = selectedItems.size
        if (count > 0) {
            bottomConfirmBar.visibility = View.VISIBLE
            val limitSuffix = config.maxFiles?.let { " / $it" } ?: ""
            selectedHintView.text = "$count$limitSuffix"
            confirmButton.text = "${config.strings.done} ($count)"
        } else {
            bottomConfirmBar.visibility = View.GONE
        }
    }

    private fun confirmAndFinish() {
        if (selectedItems.isEmpty()) return
        val uris = selectedItems.map { it.uri }
        deliveredResult = true
        dismiss()
        onResult(uris)
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

        // Video duration badge in bottom-left / 视频左下角时长标签
        if (item.isVideo) {
            val durView = TextView(hostActivity).apply {
                text = MediaStoreRepository.formatDuration(item.durationMs)
                textSize = 11f
                setTextColor(Color.WHITE)
                setPadding(
                    (6 * density).roundToInt(),
                    (2 * density).roundToInt(),
                    (6 * density).roundToInt(),
                    (2 * density).roundToInt()
                )
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

        // Top-right selection badge (with enlarged hit target) / 右上角圆形选择角标
        val selIdx = selectedItems.indexOfFirst { it.id == item.id }
        val hitSize = (38 * density).roundToInt()
        val badgeSize = (24 * density).roundToInt()
        val badgeHitArea = FrameLayout(hostActivity).apply {
            layoutParams = FrameLayout.LayoutParams(hitSize, hitSize, Gravity.TOP or Gravity.END)
            setOnClickListener { onBadgeClicked(item) }
        }
        val badgeView = TextView(hostActivity).apply {
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams =
                FrameLayout.LayoutParams(badgeSize, badgeSize, Gravity.TOP or Gravity.END).apply {
                    topMargin = (6 * density).roundToInt()
                    marginEnd = (6 * density).roundToInt()
                }
            if (selIdx >= 0) {
                text = if (config.multiple) "${selIdx + 1}" else "✓"
                setTextColor(config.theme.onPrimaryColor)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(config.theme.primaryColor)
                }
            } else {
                text = ""
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(config.theme.unselectedBadgeFillColor)
                    setStroke(
                        (1.8f * density).roundToInt(),
                        config.theme.unselectedBadgeBorderColor
                    )
                }
            }
        }
        badgeHitArea.addView(badgeView)
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
                val col =
                    (if (hasHeroCameraHeader()) position - 1 else position) % config.crossAxisCount
                val lp = holder.container.layoutParams as RecyclerView.LayoutParams
                lp.marginEnd = if (col < config.crossAxisCount - 1) spacingPx else 0
                holder.container.layoutParams = lp
                bindMediaTile(holder.container, item, itemIdx)
            }
        }
    }

    /**
     * Hero header row containing the 1x2 live camera preview tile on the left and
     * a 2-row media mini-grid on the right, matching the staggered grid layout.
     * 首行复合容器：左侧为跨 2 行的实时相机预览格，右侧为 2 行媒体缩略图网格。
     */
    private inner class HeroViewHolder(private val root: LinearLayout) :
        RecyclerView.ViewHolder(root) {

        private val cameraTile = CameraPreviewTileView(hostActivity, config.strings.cameraLabel)
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
                dismiss()
                onLaunchCamera()
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
                        layoutParams =
                            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
                                .apply {
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

    private class CellViewHolder(val container: FrameLayout) :
        RecyclerView.ViewHolder(container)
}
