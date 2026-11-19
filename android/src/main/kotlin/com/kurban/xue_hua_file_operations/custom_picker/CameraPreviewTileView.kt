package com.kurban.xue_hua_file_operations.custom_picker

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.PorterDuff
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.kurban.xue_hua_file_operations.R

/**
 * Live rear-camera preview tile rendered inside the top-left 1x2 slot of the
 * media grid. Gracefully degrades to a static dark camera button with a vector
 * icon when camera permission is not granted or no camera hardware is available.
 * 渲染在媒体网格左上角 1×2 位置的实时后置相机预览格。
 * 当未授予相机权限或设备无摄像头时，自动优雅降级为带矢量图标的静态深色拍照入口。
 */
class CameraPreviewTileView(
    context: Context,
    private val cameraLabel: String,
) : FrameLayout(context) {

    private val textureView = TextureView(context)
    private val badgeContainer = FrameLayout(context)
    private val fallbackContainer = LinearLayout(context)

    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var previewSize: Size = Size(640, 480)
    private var isStarted = false

    init {
        setBackgroundColor(0xFF202225.toInt())
        clipToOutline = true

        textureView.layoutParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.MATCH_PARENT
        )
        addView(textureView)

        val density = resources.displayMetrics.density

        // Fallback container with vector camera icon + label
        // 未授权或无摄像头时的降级视图（矢量相机图标 + 文案）
        fallbackContainer.apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
            addView(ImageView(context).apply {
                setImageResource(R.drawable.xh_ic_camera)
                setColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN)
                val iconPx = (30 * density).toInt()
                layoutParams = LinearLayout.LayoutParams(iconPx, iconPx)
            })
            addView(TextView(context).apply {
                text = cameraLabel
                setTextColor(Color.WHITE)
                textSize = 13f
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = (6 * density).toInt()
                }
            })
        }
        addView(fallbackContainer)

        // Top-right circular camera icon badge shown over live preview
        // 实时预览画面右上角的圆形矢量相机角标
        badgeContainer.apply {
            val badgePx = (32 * density).toInt()
            val marginPx = (8 * density).toInt()
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x55000000)
            }
            layoutParams = LayoutParams(badgePx, badgePx, Gravity.TOP or Gravity.END).apply {
                topMargin = marginPx
                marginEnd = marginPx
            }
            addView(ImageView(context).apply {
                setImageResource(R.drawable.xh_ic_camera)
                setColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN)
                val iconPx = (18 * density).toInt()
                layoutParams = LayoutParams(iconPx, iconPx, Gravity.CENTER)
            })
            visibility = GONE
        }
        addView(badgeContainer)

        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(
                surface: SurfaceTexture,
                width: Int,
                height: Int
            ) {
                if (isStarted) {
                    openCameraIfPermitted(width, height)
                }
            }

            override fun onSurfaceTextureSizeChanged(
                surface: SurfaceTexture,
                width: Int,
                height: Int
            ) {
                configureTransform(width, height)
            }

            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                closeCamera()
                return true
            }

            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
        }
    }

    /**
     * Starts live camera preview when permission is granted; otherwise shows
     * the static fallback button.
     * 在已获相机权限时开启实时预览；否则展示静态降级按钮。
     */
    fun startPreview() {
        isStarted = true
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPermission) {
            fallbackContainer.visibility = VISIBLE
            badgeContainer.visibility = GONE
            return
        }
        fallbackContainer.visibility = GONE
        badgeContainer.visibility = VISIBLE
        if (textureView.isAvailable) {
            openCameraIfPermitted(textureView.width, textureView.height)
        }
    }

    /**
     * Stops the active camera preview and releases hardware resources.
     * 停止实时预览并释放摄像头硬件资源。
     */
    fun stopPreview() {
        isStarted = false
        closeCamera()
    }

    @SuppressLint("MissingPermission")
    private fun openCameraIfPermitted(viewWidth: Int, viewHeight: Int) {
        if (cameraDevice != null) return
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return

        try {
            val manager =
                context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
            val cameraId = manager.cameraIdList.firstOrNull { id ->
                val chars = manager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: manager.cameraIdList.firstOrNull() ?: return

            val chars = manager.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val choices = map?.getOutputSizes(SurfaceTexture::class.java)
            if (!choices.isNullOrEmpty()) {
                previewSize = choices.minByOrNull { size ->
                    kotlin.math.abs(size.width * size.height - 640 * 480)
                } ?: choices.first()
            }

            startBackgroundThread()
            configureTransform(viewWidth, viewHeight)
            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    if (!isStarted) {
                        camera.close()
                        return
                    }
                    cameraDevice = camera
                    createPreviewSession(camera)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                }
            }, cameraHandler)
        } catch (_: Exception) {
            fallbackContainer.visibility = VISIBLE
            badgeContainer.visibility = GONE
        }
    }

    private fun createPreviewSession(camera: CameraDevice) {
        val surfaceTexture = textureView.surfaceTexture ?: return
        surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
        val surface = Surface(surfaceTexture)
        try {
            val requestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(surface)
                set(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                )
            }
            val callback = object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (cameraDevice == null || !isStarted) return
                    captureSession = session
                    try {
                        session.setRepeatingRequest(requestBuilder.build(), null, cameraHandler)
                    } catch (_: Exception) {
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) = Unit
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val config = SessionConfiguration(
                    SessionConfiguration.SESSION_REGULAR,
                    listOf(OutputConfiguration(surface)),
                    { command -> cameraHandler?.post(command) ?: command.run() },
                    callback
                )
                camera.createCaptureSession(config)
            } else {
                @Suppress("DEPRECATION")
                camera.createCaptureSession(listOf(surface), callback, cameraHandler)
            }
        } catch (_: Exception) {
        }
    }

    private fun configureTransform(viewWidth: Int, viewHeight: Int) {
        if (viewWidth <= 0 || viewHeight <= 0) return
        val matrix = Matrix()
        val bufferW = previewSize.height.toFloat() // Portrait sensor aspect / 竖屏传感器比例
        val bufferH = previewSize.width.toFloat()
        val scale = maxOf(viewWidth / bufferW, viewHeight / bufferH)
        val scaledW = bufferW * scale
        val scaledH = bufferH * scale
        matrix.setScale(scaledW / viewWidth, scaledH / viewHeight, viewWidth / 2f, viewHeight / 2f)
        textureView.setTransform(matrix)
    }

    private fun startBackgroundThread() {
        if (cameraThread != null) return
        cameraThread = HandlerThread("XueHuaCameraTile").also {
            it.start()
            cameraHandler = Handler(it.looper)
        }
    }

    private fun closeCamera() {
        try {
            captureSession?.close()
        } catch (_: Exception) {
        }
        captureSession = null
        try {
            cameraDevice?.close()
        } catch (_: Exception) {
        }
        cameraDevice = null
        cameraThread?.quitSafely()
        cameraThread = null
        cameraHandler = null
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        closeCamera()
    }
}
