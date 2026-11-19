package com.kurban.xue_hua_file_operations.custom_picker

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.VideoView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView

/**
 * Full-screen native media preview dialog supporting horizontal swiping,
 * high-resolution image viewing, inline video playback, and live selection sync.
 * 原生全屏媒体预览弹窗，支持横向滑动切换、高清大图查看、视频内联播放及与网格实时同步的勾选状态。
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
) : Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentIndex: Int = initialIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0))

    private lateinit var recyclerView: RecyclerView
    private lateinit var counterView: TextView
    private lateinit var selectBadge: TextView
    private lateinit var confirmButton: TextView
    private var activeVideoView: VideoView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.BLACK))
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        }

        val density = context.resources.displayMetrics.density
        fun dp(v: Int): Int = (v * density).toInt()

        val root = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
        }

        // Horizontal paged RecyclerView / 横向分页滑动列表
        recyclerView = RecyclerView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
            adapter = PreviewAdapter()
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
        root.addView(recyclerView)

        // Top floating bar / 顶部悬浮操作栏
        val topBar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(36), dp(16), dp(12))
            setBackgroundColor(0x66000000)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val backButton = TextView(context).apply {
            text = "←"
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x55000000)
            }
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
            setOnClickListener { dismiss() }
        }
        topBar.addView(backButton)

        counterView = TextView(context).apply {
            textSize = 16f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        topBar.addView(counterView)

        selectBadge = TextView(context).apply {
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(dp(32), dp(32))
            setOnClickListener {
                val item = items.getOrNull(currentIndex) ?: return@setOnClickListener
                if (onToggleSelection(item)) {
                    refreshControls()
                }
            }
        }
        topBar.addView(selectBadge)
        root.addView(topBar)

        // Bottom confirm bar / 底部确认操作栏
        val bottomBar = FrameLayout(context).apply {
            setPadding(dp(16), dp(12), dp(16), dp(24))
            setBackgroundColor(0x66000000)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        confirmButton = TextView(context).apply {
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(config.theme.onPrimaryColor)
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(10), dp(20), dp(10))
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
                // In single-select mode, confirming with nothing selected picks the current item.
                // 单选模式下若未显式勾选，点击完成将直接选中当前预览项。
                if (!config.multiple && selectedItems.isEmpty()) {
                    items.getOrNull(currentIndex)?.let { onToggleSelection(it) }
                }
                if (selectedItems.isNotEmpty()) {
                    dismiss()
                    onConfirmSelection()
                }
            }
        }
        bottomBar.addView(confirmButton)
        root.addView(bottomBar)

        setContentView(root)
        recyclerView.scrollToPosition(currentIndex)
        refreshControls()
    }

    override fun dismiss() {
        stopActiveVideo()
        super.dismiss()
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

        val density = context.resources.displayMetrics.density
        if (selIdx >= 0) {
            selectBadge.text = if (config.multiple) "${selIdx + 1}" else "✓"
            selectBadge.setTextColor(config.theme.onPrimaryColor)
            selectBadge.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(config.theme.primaryColor)
            }
        } else {
            selectBadge.text = ""
            selectBadge.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(config.theme.unselectedBadgeFillColor)
                setStroke((2 * density).toInt(), config.theme.unselectedBadgeBorderColor)
            }
        }

        val count = selectedItems.size
        confirmButton.text = if (count > 0) "${config.strings.done} ($count)" else config.strings.done
        confirmButton.alpha = if (count > 0 || !config.multiple) 1f else 0.5f
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

        private val imageView = ImageView(container.context).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
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

        private val playButton = TextView(container.context).apply {
            text = "▶"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            val size = (64 * container.resources.displayMetrics.density).toInt()
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x88000000.toInt())
            }
            layoutParams = FrameLayout.LayoutParams(size, size, Gravity.CENTER)
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
}
