package com.kurban.xue_hua_file_operations.custom_picker

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.annotation.SuppressLint
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.PointF
import android.graphics.PorterDuff
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.GestureDetector
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.VideoView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView
import com.kurban.xue_hua_file_operations.R
import kotlin.math.roundToInt

/**
 * Full-screen immersive native media preview dialog for Android.
 * Features smooth zoom/fade entrance & exit transitions, pinch & double-tap zoom,
 * tap-to-toggle chrome, soft gradient top/bottom bars, a horizontal selected-media
 * thumbnail strip, inline video playback, and live selection synchronization.
 *
 * Android 原生沉浸式全屏媒体预览弹窗。
 * 支持平滑缩放淡入/淡出入场退场动画、双指捏合与双击缩放、轻触切换工具栏显隐、
 * 顶部/底部渐变蒙层、底部已选缩略图快速跳转条、视频内联播放及与主网格实时同步的勾选状态。
 */
class CustomMediaPreviewDialog(
    context: Context,
    private val config: CustomMediaPickerConfig,
    private val repository: MediaStoreRepository,
    private val items: List<MediaItem>,
    private val initialIndex: Int,
    private val selectedItems: MutableList<MediaItem>,
    private val onToggleSelection: (MediaItem) -> Boolean,
    private val onConfirmSelection: () -> Unit,
) : Dialog(context, android.R.style.Theme_Translucent_NoTitleBar) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val easeOutInterpolator = PathInterpolator(0.22f, 1f, 0.36f, 1f)
    private var currentIndex: Int = initialIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0))
    private var isChromeVisible = true
    private var isDismissing = false
    private var statusBarHeightPx = 0
    private var navBarHeightPx = 0

    private lateinit var rootContainer: FrameLayout
    private lateinit var contentContainer: FrameLayout
    private lateinit var recyclerView: RecyclerView
    private lateinit var topChrome: FrameLayout
    private lateinit var bottomChrome: LinearLayout
    private lateinit var counterView: TextView
    private lateinit var selectBadgeContainer: FrameLayout
    private lateinit var selectBadgeNumber: TextView
    private lateinit var selectBadgeCheck: ImageView
    private lateinit var selectedStripRecycler: RecyclerView
    private lateinit var confirmButton: TextView
    private var activeVideoView: VideoView? = null
    private var lastRenderedStripIds: List<Long> = emptyList()

    private val selectedStripAdapter = SelectedStripAdapter()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        configureEdgeToEdgeWindow()

        val density = context.resources.displayMetrics.density
        fun dp(v: Int): Int = (v * density).roundToInt()

        rootContainer = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            alpha = 0f
        }

        contentContainer = FrameLayout(context).apply {
            scaleX = 0.93f
            scaleY = 0.93f
            alpha = 0f
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        rootContainer.addView(contentContainer)

        // Horizontal paged media viewer / 横向分页滑动媒体浏览器
        recyclerView = RecyclerView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
            adapter = PreviewAdapter()
            overScrollMode = View.OVER_SCROLL_NEVER
        }
        val snapHelper = PagerSnapHelper()
        snapHelper.attachToRecyclerView(recyclerView)
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    val snapView = snapHelper.findSnapView(rv.layoutManager) ?: return
                    val pos = rv.getChildAdapterPosition(snapView)
                    if (pos in items.indices && pos != currentIndex) {
                        stopActiveVideo()
                        currentIndex = pos
                        refreshControls()
                    }
                }
            }
        })
        contentContainer.addView(recyclerView)

        // Transparent floating top bar / 全透明顶部悬浮操作栏
        topChrome = FrameLayout(context).apply {
            setBackgroundColor(Color.TRANSPARENT)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val topRow = FrameLayout(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(52)
            )
        }

        val backButton = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x52000000)
                setStroke(dp(1), 0x26FFFFFF)
            }
            layoutParams = FrameLayout.LayoutParams(dp(40), dp(40), Gravity.START or Gravity.CENTER_VERTICAL)
            addView(ImageView(context).apply {
                setImageResource(R.drawable.xh_ic_arrow_back)
                setColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN)
                layoutParams = FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER)
            })
            setOnClickListener { dismissAnimated() }
        }
        topRow.addView(backButton)

        counterView = TextView(context).apply {
            textSize = 15f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(5), dp(12), dp(5))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(14).toFloat()
                setColor(0x48000000)
            }
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }
        topRow.addView(counterView)

        val badgeHitArea = FrameLayout(context).apply {
            layoutParams = FrameLayout.LayoutParams(dp(44), dp(44), Gravity.END or Gravity.CENTER_VERTICAL)
            setOnClickListener {
                val item = items.getOrNull(currentIndex) ?: return@setOnClickListener
                if (onToggleSelection(item)) {
                    animateBadgeBounce()
                    refreshControls()
                }
            }
        }
        selectBadgeContainer = FrameLayout(context).apply {
            layoutParams = FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER)
        }
        selectBadgeNumber = TextView(context).apply {
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        selectBadgeCheck = ImageView(context).apply {
            setImageResource(R.drawable.xh_ic_check)
            setColorFilter(config.theme.onPrimaryColor, PorterDuff.Mode.SRC_IN)
            layoutParams = FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER)
            visibility = View.GONE
        }
        selectBadgeContainer.addView(selectBadgeNumber)
        selectBadgeContainer.addView(selectBadgeCheck)
        badgeHitArea.addView(selectBadgeContainer)
        topRow.addView(badgeHitArea)

        topChrome.addView(topRow)
        contentContainer.addView(topChrome)

        // Transparent floating bottom bar + selected thumbnail strip + confirm button
        // 全透明底部悬浮操作栏 + 已选缩略图快速跳转条 + 右侧完成按钮
        bottomChrome = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.TRANSPARENT)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        selectedStripRecycler = RecyclerView(context).apply {
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
            adapter = selectedStripAdapter
            itemAnimator = null
            clipToPadding = false
            setPadding(dp(16), dp(8), dp(16), dp(8))
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(68)
            )
        }
        bottomChrome.addView(selectedStripRecycler)

        val actionRow = FrameLayout(context).apply {
            setPadding(dp(16), dp(6), dp(16), dp(12))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        confirmButton = TextView(context).apply {
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.onPrimaryColor)
            gravity = Gravity.CENTER
            setPadding(dp(22), dp(10), dp(22), dp(10))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(22).toFloat()
                setColor(config.theme.primaryColor)
            }
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.END or Gravity.CENTER_VERTICAL
            )
            setOnClickListener {
                if (!config.multiple && selectedItems.isEmpty()) {
                    items.getOrNull(currentIndex)?.let { onToggleSelection(it) }
                }
                if (selectedItems.isNotEmpty()) {
                    dismissAnimated { onConfirmSelection() }
                }
            }
        }
        actionRow.addView(confirmButton)
        bottomChrome.addView(actionRow)
        contentContainer.addView(bottomChrome)

        ViewCompat.setOnApplyWindowInsetsListener(rootContainer) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            statusBarHeightPx = bars.top
            navBarHeightPx = bars.bottom
            topChrome.setPadding(dp(14), statusBarHeightPx + dp(6), dp(14), dp(18))
            bottomChrome.setPadding(0, dp(16), 0, navBarHeightPx + dp(4))
            insets
        }

        setContentView(rootContainer)
        setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                dismissAnimated()
                true
            } else {
                false
            }
        }

        recyclerView.scrollToPosition(currentIndex)
        refreshControls()

        // Smooth unified entrance animation / 统一平滑缩放淡入动画
        rootContainer.post {
            rootContainer.animate()
                .alpha(1f)
                .setDuration(220)
                .setInterpolator(DecelerateInterpolator())
                .start()
            contentContainer.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(240)
                .setInterpolator(easeOutInterpolator)
                .start()
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
        controller.isAppearanceLightStatusBars = false
        controller.isAppearanceLightNavigationBars = false
    }

    private fun dismissAnimated(afterDismiss: (() -> Unit)? = null) {
        if (isDismissing) return
        isDismissing = true
        stopActiveVideo()
        rootContainer.animate()
            .alpha(0f)
            .setDuration(190)
            .setInterpolator(DecelerateInterpolator())
            .start()
        contentContainer.animate()
            .alpha(0f)
            .scaleX(0.93f)
            .scaleY(0.93f)
            .setDuration(190)
            .setInterpolator(DecelerateInterpolator())
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    super@CustomMediaPreviewDialog.dismiss()
                    afterDismiss?.invoke()
                }
            })
            .start()
    }

    override fun dismiss() {
        stopActiveVideo()
        super.dismiss()
    }

    private fun toggleChrome() {
        isChromeVisible = !isChromeVisible
        val targetAlpha = if (isChromeVisible) 1f else 0f
        topChrome.animate().alpha(targetAlpha).setDuration(180).withStartAction {
            if (isChromeVisible) topChrome.visibility = View.VISIBLE
        }.withEndAction {
            if (!isChromeVisible) topChrome.visibility = View.INVISIBLE
        }.start()
        bottomChrome.animate().alpha(targetAlpha).setDuration(180).withStartAction {
            if (isChromeVisible) bottomChrome.visibility = View.VISIBLE
        }.withEndAction {
            if (!isChromeVisible) bottomChrome.visibility = View.INVISIBLE
        }.start()
    }

    private fun animateBadgeBounce() {
        selectBadgeContainer.scaleX = 0.8f
        selectBadgeContainer.scaleY = 0.8f
        selectBadgeContainer.animate()
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(180)
            .setInterpolator(easeOutInterpolator)
            .start()
    }

    private fun stopActiveVideo() {
        try {
            activeVideoView?.stopPlayback()
        } catch (_: Exception) {
        }
        activeVideoView = null
    }

    private fun refreshControls() {
        counterView.text = "${currentIndex + 1} / ${items.size}"
        val currentItem = items.getOrNull(currentIndex)
        val selIdx = if (currentItem != null) {
            selectedItems.indexOfFirst { it.id == currentItem.id }
        } else {
            -1
        }
        val limitReached = config.multiple && config.maxFiles != null &&
                selectedItems.size >= config.maxFiles && selIdx < 0

        val density = context.resources.displayMetrics.density
        if (selIdx >= 0) {
            selectBadgeContainer.alpha = 1f
            selectBadgeContainer.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(config.theme.primaryColor)
            }
            if (config.multiple) {
                selectBadgeCheck.visibility = View.GONE
                selectBadgeNumber.visibility = View.VISIBLE
                selectBadgeNumber.text = "${selIdx + 1}"
                selectBadgeNumber.setTextColor(config.theme.onPrimaryColor)
            } else {
                selectBadgeNumber.visibility = View.GONE
                selectBadgeCheck.visibility = View.VISIBLE
            }
        } else {
            selectBadgeNumber.visibility = View.GONE
            selectBadgeCheck.visibility = View.GONE
            selectBadgeContainer.alpha = if (limitReached) 0.45f else 1f
            selectBadgeContainer.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(config.theme.unselectedBadgeFillColor)
                setStroke((2 * density).roundToInt(), config.theme.unselectedBadgeBorderColor)
            }
        }

        val count = selectedItems.size
        confirmButton.text = if (count > 0) "${config.strings.done} ($count)" else config.strings.done
        confirmButton.alpha = if (count > 0 || !config.multiple) 1f else 0.78f

        // Selected thumbnail strip in multi-select mode / 多选模式底部已选缩略图条
        if (config.multiple && selectedItems.isNotEmpty()) {
            selectedStripRecycler.visibility = View.VISIBLE
            val stripIds = selectedItems.map { it.id }
            if (stripIds != lastRenderedStripIds) {
                lastRenderedStripIds = stripIds
                selectedStripAdapter.notifyDataSetChanged()
            } else {
                // Only update border highlight in place on page swipe (zero flash).
                // 滑动切换页面时仅就地更新边框高亮，不调用 notifyDataSetChanged，彻底杜绝闪烁。
                updateVisibleStripHighlights()
            }
        } else {
            lastRenderedStripIds = emptyList()
            selectedStripRecycler.visibility = View.GONE
        }
    }

    private fun updateVisibleStripHighlights() {
        for (i in 0 until selectedStripRecycler.childCount) {
            val child = selectedStripRecycler.getChildAt(i) ?: continue
            (selectedStripRecycler.getChildViewHolder(child) as? SelectedStripHolder)?.updateHighlightOnly()
        }
    }

    private inner class SelectedStripAdapter : RecyclerView.Adapter<SelectedStripHolder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SelectedStripHolder {
            val density = parent.resources.displayMetrics.density
            val size = (50 * density).roundToInt()
            val frame = FrameLayout(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(size, size).apply {
                    marginEnd = (8 * density).roundToInt()
                }
            }
            return SelectedStripHolder(frame)
        }

        override fun getItemCount(): Int = selectedItems.size

        override fun onBindViewHolder(holder: SelectedStripHolder, position: Int) {
            holder.bind(selectedItems[position])
        }
    }

    private inner class SelectedStripHolder(private val container: FrameLayout) :
        RecyclerView.ViewHolder(container) {
        private val density = container.resources.displayMetrics.density
        private val imageView = ImageView(container.context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            clipToOutline = true
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 8 * density
                setColor(0x33FFFFFF)
            }
            val pad = (2 * density).roundToInt()
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ).apply {
                setMargins(pad, pad, pad, pad)
            }
        }
        private var boundId: Long = -1L

        init {
            container.addView(imageView)
        }

        fun updateHighlightOnly() {
            val isCurrent = boundId != -1L && items.getOrNull(currentIndex)?.id == boundId
            container.background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 10 * density
                setColor(Color.TRANSPARENT)
                if (isCurrent) {
                    setStroke((2.2f * density).roundToInt(), config.theme.primaryColor)
                }
            }
        }

        fun bind(item: MediaItem) {
            val idChanged = boundId != item.id
            boundId = item.id
            updateHighlightOnly()
            if (idChanged) {
                boundId = item.id
                imageView.setImageBitmap(null)
                repository.loadThumbnail(item.uri, (120 * density).roundToInt(), item.isVideo) { bmp ->
                    mainHandler.post {
                        if (boundId == item.id && bmp != null) {
                            imageView.setImageBitmap(bmp)
                        }
                    }
                }
            }
            container.setOnClickListener {
                val targetIndex = items.indexOfFirst { it.id == item.id }
                if (targetIndex >= 0 && targetIndex != currentIndex) {
                    stopActiveVideo()
                    currentIndex = targetIndex
                    recyclerView.scrollToPosition(targetIndex)
                    refreshControls()
                }
            }
        }
    }

    private inner class PreviewAdapter : RecyclerView.Adapter<PreviewHolder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PreviewHolder {
            val container = FrameLayout(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
            return PreviewHolder(container)
        }

        override fun getItemCount(): Int = items.size

        override fun onBindViewHolder(holder: PreviewHolder, position: Int) {
            holder.bind(items[position])
        }
    }

    private inner class PreviewHolder(private val container: FrameLayout) :
        RecyclerView.ViewHolder(container) {

        private val imageView = ZoomablePreviewImageView(container.context) {
            toggleChrome()
        }.apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        private val videoView = VideoView(container.context).apply {
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        private val playButton = FrameLayout(container.context).apply {
            val density = container.resources.displayMetrics.density
            val size = (66 * density).roundToInt()
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x78000000)
                setStroke((1.5f * density).roundToInt(), 0x55FFFFFF)
            }
            layoutParams = FrameLayout.LayoutParams(size, size, Gravity.CENTER)
            addView(ImageView(container.context).apply {
                setImageResource(R.drawable.xh_ic_play_arrow)
                setColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN)
                val iconPx = (34 * density).roundToInt()
                layoutParams = FrameLayout.LayoutParams(iconPx, iconPx, Gravity.CENTER)
            })
            visibility = View.GONE
        }

        private var boundId: Long = -1L

        init {
            container.addView(imageView)
            container.addView(videoView)
            container.addView(playButton)
        }

        fun bind(item: MediaItem) {
            boundId = item.id
            videoView.visibility = View.GONE
            imageView.visibility = View.VISIBLE
            imageView.resetZoom()
            imageView.setImageBitmap(null)
            playButton.visibility = if (item.isVideo) View.VISIBLE else View.GONE

            val maxDim = maxOf(
                container.resources.displayMetrics.widthPixels,
                container.resources.displayMetrics.heightPixels
            ).coerceAtMost(1920)
            repository.loadPreviewBitmap(item.uri, maxDim, item.isVideo) { bmp ->
                mainHandler.post {
                    if (boundId == item.id && bmp != null) {
                        imageView.setImageBitmap(bmp)
                    }
                }
            }

            playButton.setOnClickListener {
                stopActiveVideo()
                imageView.visibility = View.GONE
                playButton.visibility = View.GONE
                videoView.visibility = View.VISIBLE
                videoView.setVideoURI(item.uri)
                videoView.setOnCompletionListener {
                    videoView.visibility = View.GONE
                    imageView.visibility = View.VISIBLE
                    playButton.visibility = View.VISIBLE
                    activeVideoView = null
                }
                videoView.start()
                activeVideoView = videoView
            }

            videoView.setOnClickListener {
                if (videoView.isPlaying) {
                    videoView.pause()
                    playButton.visibility = View.VISIBLE
                } else {
                    videoView.start()
                    playButton.visibility = View.GONE
                }
            }
        }
    }

    /**
     * Lightweight pinch-to-zoom & double-tap zoom ImageView for full-screen
     * preview that yields horizontal swipes to the parent RecyclerView at 1x zoom.
     * 轻量级全屏预览缩放 ImageView：支持双指缩放与双击放大/还原，1x 时将横向滑动交还分页列表。
     */
    @SuppressLint("ClickableViewAccessibility")
    private class ZoomablePreviewImageView(
        context: Context,
        private val onSingleTap: () -> Unit,
    ) : ImageView(context) {

        private var currentScale = 1f
        private val minScale = 1f
        private val maxScale = 3.5f
        private val lastTouch = PointF()
        private var translateX = 0f
        private var translateY = 0f

        private val scaleDetector = ScaleGestureDetector(
            context,
            object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    val next = (currentScale * detector.scaleFactor).coerceIn(minScale, maxScale)
                    currentScale = next
                    if (currentScale <= 1.01f) {
                        resetZoom()
                    } else {
                        applyZoomTransform()
                    }
                    return true
                }
            }
        )

        private val gestureDetector = GestureDetector(
            context,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    onSingleTap()
                    return true
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    if (currentScale > 1.05f) {
                        resetZoom()
                    } else {
                        currentScale = 2.4f
                        translateX = 0f
                        translateY = 0f
                        applyZoomTransform()
                    }
                    return true
                }
            }
        )

        init {
            scaleType = ScaleType.FIT_CENTER
        }

        fun resetZoom() {
            currentScale = 1f
            translateX = 0f
            translateY = 0f
            animate().scaleX(1f).scaleY(1f).translationX(0f).translationY(0f).setDuration(160).start()
        }

        private fun applyZoomTransform() {
            val maxTx = (width * (currentScale - 1f)) / 2f
            val maxTy = (height * (currentScale - 1f)) / 2f
            translateX = translateX.coerceIn(-maxTx, maxTx)
            translateY = translateY.coerceIn(-maxTy, maxTy)
            scaleX = currentScale
            scaleY = currentScale
            translationX = translateX
            translationY = translateY
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            scaleDetector.onTouchEvent(event)
            gestureDetector.onTouchEvent(event)

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    lastTouch.set(event.x, event.y)
                    parent?.requestDisallowInterceptTouchEvent(currentScale > 1.05f)
                }

                MotionEvent.ACTION_MOVE -> {
                    if (currentScale > 1.05f && !scaleDetector.isInProgress) {
                        parent?.requestDisallowInterceptTouchEvent(true)
                        translateX += (event.x - lastTouch.x)
                        translateY += (event.y - lastTouch.y)
                        lastTouch.set(event.x, event.y)
                        applyZoomTransform()
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    parent?.requestDisallowInterceptTouchEvent(false)
                }
            }
            return true
        }
    }
}
