package com.teampara.setflow

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.Display
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.TextView
import android.widget.FrameLayout
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil

/** A compact native window; only its own bounds intercept touches. */
class RestTimerOverlay(
    private val appContext: Context,
    private val onClose: () -> Unit,
    private val onReturnToWorkout: () -> Unit,
) {
    private val context: Context by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val display = appContext.getSystemService(DisplayManager::class.java)
                .getDisplay(Display.DEFAULT_DISPLAY)
            appContext.createDisplayContext(display).createWindowContext(
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                null,
            )
        } else {
            appContext
        }
    }
    private val windowManager by lazy { context.getSystemService(WindowManager::class.java) }
    private val handler = Handler(Looper.getMainLooper())
    private var root: View? = null
    private var layout: WindowManager.LayoutParams? = null
    private var endsAt = 0L
    private var positionX: Int? = null
    private var positionY: Int? = null
    private val tick = object : Runnable {
        override fun run() {
            val view = root ?: return
            if (!Settings.canDrawOverlays(context) || endsAt <= System.currentTimeMillis()) {
                hide()
                return
            }
            updateTime(view)
            handler.postDelayed(this, 250L)
        }
    }

    fun show(timerEndsAt: Long, detail: String) {
        endsAt = timerEndsAt
        if (!Settings.canDrawOverlays(context)) {
            hide()
            return
        }
        root?.let { view ->
            view.findViewById<TextView>(R.id.rest_overlay_detail).text = detail
            updateTime(view)
            fitWithinScreen(view)
            updateWindow(view)
            return
        }
        val view = LayoutInflater.from(context).inflate(
            R.layout.rest_timer_overlay,
            FrameLayout(context),
            false,
        )
        view.clipToOutline = true
        view.findViewById<TextView>(R.id.rest_overlay_detail).text = detail
        view.findViewById<View>(R.id.rest_overlay_close).setOnClickListener { onClose() }
        view.findViewById<View>(R.id.rest_overlay_return).setOnClickListener {
            // Keep the visible window until startActivity has been requested.
            onReturnToWorkout()
        }
        installDrag(view.findViewById(R.id.rest_overlay_timer))
        installDrag(view.findViewById(R.id.rest_overlay_title))
        @Suppress("DEPRECATION")
        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        layout = WindowManager.LayoutParams(
            1,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            title = context.getString(R.string.rest_overlay_title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setFitInsetsTypes(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER
            }
        }
        fitWithinScreen(view)
        updateTime(view)
        try {
            windowManager.addView(view, layout)
            root = view
            view.post {
                if (root === view) {
                    fitWithinScreen(view)
                    updateWindow(view)
                }
            }
            handler.post(tick)
        } catch (_: RuntimeException) {
            // Revocation and vendor window restrictions must not stop the timer.
            layout = null
        }
    }

    fun hide() {
        handler.removeCallbacks(tick)
        val view = root ?: return
        root = null
        layout?.let {
            positionX = it.x
            positionY = it.y
        }
        layout = null
        try {
            windowManager.removeViewImmediate(view)
        } catch (_: IllegalArgumentException) {
            // Android may already have removed the window on permission revoke.
        }
    }

    private fun updateTime(view: View) {
        val remaining = ceil(
            (endsAt - System.currentTimeMillis()).coerceAtLeast(0L) / 1_000.0,
        ).toInt()
        val timer = view.findViewById<TextView>(R.id.rest_overlay_timer)
        val time = String.format(Locale.ROOT, "%d:%02d", remaining / 60, remaining % 60)
        if (timer.text.toString() == time) return
        timer.text = time
        timer.contentDescription = context.getString(
            R.string.rest_overlay_remaining,
            remaining / 60,
            remaining % 60,
        )
    }

    private fun installDrag(handle: View) {
        val slop = ViewConfiguration.get(context).scaledTouchSlop
        var rawX = 0f
        var rawY = 0f
        var initialX = 0
        var initialY = 0
        var dragging = false
        handle.setOnTouchListener { view, event ->
            val params = layout ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    rawX = event.rawX
                    rawY = event.rawY
                    initialX = params.x
                    initialY = params.y
                    dragging = false
                    view.parent.requestDisallowInterceptTouchEvent(true)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - rawX
                    val dy = event.rawY - rawY
                    if (abs(dx) > slop || abs(dy) > slop) dragging = true
                    if (dragging) {
                        val direction = if (view.layoutDirection == View.LAYOUT_DIRECTION_RTL) -1 else 1
                        positionX = initialX + dx.toInt() * direction
                        positionY = initialY + dy.toInt()
                        root?.let {
                            fitWithinScreen(it)
                            updateWindow(it)
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    view.parent.requestDisallowInterceptTouchEvent(false)
                    if (!dragging && event.actionMasked == MotionEvent.ACTION_UP) view.performClick()
                    true
                }
                else -> false
            }
        }
    }

    private fun fitWithinScreen(view: View) {
        val params = layout ?: return
        val size = usableSize()
        val margin = context.resources.getDimensionPixelSize(R.dimen.rest_overlay_gap)
        params.width = context.resources.getDimensionPixelSize(R.dimen.rest_overlay_width)
            .coerceAtMost((size.x - margin * 2).coerceAtLeast(1))
        val maxHeight = (size.y - margin * 2).coerceAtLeast(1)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(params.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(maxHeight, View.MeasureSpec.AT_MOST),
        )
        // The panel grows with system font scale. Short screens scroll its content.
        params.height = view.measuredHeight.coerceIn(1, maxHeight)
        val maxX = (size.x - params.width - margin).coerceAtLeast(margin)
        val maxY = (size.y - params.height - margin).coerceAtLeast(margin)
        params.x = (positionX ?: maxX).coerceIn(margin, maxX)
        params.y = (positionY ?: margin).coerceIn(margin, maxY)
    }

    private fun usableSize(): Point {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = windowManager.currentWindowMetrics
            val insets = metrics.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
            )
            return Point(
                metrics.bounds.width() - insets.left - insets.right,
                metrics.bounds.height() - insets.top - insets.bottom,
            )
        }
        val visibleFrame = Rect()
        root?.getWindowVisibleDisplayFrame(visibleFrame)
        if (!visibleFrame.isEmpty) return Point(visibleFrame.width(), visibleFrame.height())
        // Before attachment the legacy display supplies a provisional frame;
        // after attachment we clamp to the actual visible window frame above.
        @Suppress("DEPRECATION")
        return Point().also { windowManager.defaultDisplay.getSize(it) }
    }

    private fun updateWindow(view: View) {
        try {
            windowManager.updateViewLayout(view, layout)
        } catch (_: RuntimeException) {
            hide()
        }
    }
}
