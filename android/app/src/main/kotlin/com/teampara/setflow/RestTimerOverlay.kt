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
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
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
    private val onExtend: () -> Unit,
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
    private var detail = ""
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
        this.detail = detail
        if (!Settings.canDrawOverlays(context)) {
            hide()
            return
        }
        root?.let { view ->
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
        view.findViewById<View>(R.id.rest_overlay_close).setOnClickListener { onClose() }
        view.findViewById<View>(R.id.rest_overlay_extend).setOnClickListener { onExtend() }
        val returnControl = view.findViewById<View>(R.id.rest_overlay_return)
        returnControl.setOnClickListener {
            // Keep the visible window until startActivity has been requested.
            onReturnToWorkout()
        }
        returnControl.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = Button::class.java.name
            }
        }
        // One large time/return target: tap to return, drag to move. Buttons
        // below keep their own gestures so a drag cannot accidentally end rest.
        installDrag(returnControl)
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
        updateTime(view)
        fitWithinScreen(view)
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
        if (timer.text.toString() != time) timer.text = time
        val remainingDescription = context.getString(
            R.string.rest_overlay_remaining,
            remaining / 60,
            remaining % 60,
        )
        timer.contentDescription = remainingDescription
        // Preserve workout context for accessibility without a multi-line
        // description growing the floating window over another app.
        view.findViewById<View>(R.id.rest_overlay_return).contentDescription = context.getString(
            R.string.rest_overlay_return_description,
            remainingDescription,
            detail,
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
                    view.drawableHotspotChanged(event.x, event.y)
                    view.isPressed = true
                    view.parent.requestDisallowInterceptTouchEvent(true)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - rawX
                    val dy = event.rawY - rawY
                    if (abs(dx) > slop || abs(dy) > slop) {
                        dragging = true
                        view.isPressed = false
                    }
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
                    view.isPressed = false
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
        params.width = preferredWidth(view)
            .coerceAtMost((size.x - margin * 2).coerceAtLeast(1))
        val timer = view.findViewById<TextView>(R.id.rest_overlay_timer)
        val title = view.findViewById<TextView>(R.id.rest_overlay_title)
        val padding = context.resources.getDimensionPixelSize(R.dimen.rest_overlay_padding)
        val returnWidth = timeTextWidth(timer) +
            title.paint.measureText(title.text.toString()) + margin
        // On a narrow display, keep the enlarged countdown fully readable.
        // The whole time row still returns to the workout and retains its label
        // for accessibility when the visible caption cannot fit beside it.
        title.visibility = if (returnWidth <= params.width - padding * 2) View.VISIBLE else View.GONE
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

    private fun preferredWidth(view: View): Int {
        val resources = context.resources
        val padding = resources.getDimensionPixelSize(R.dimen.rest_overlay_padding)
        val gap = resources.getDimensionPixelSize(R.dimen.rest_overlay_gap)
        val timer = view.findViewById<TextView>(R.id.rest_overlay_timer)
        val title = view.findViewById<TextView>(R.id.rest_overlay_title)
        val extend = view.findViewById<TextView>(R.id.rest_overlay_extend)
        val close = view.findViewById<TextView>(R.id.rest_overlay_close)
        // Grow for actual scaled text rather than compressing accessibility
        // fonts into the default small card. The screen still bounds the window.
        val timeWidth = timeTextWidth(timer)
        val returnWidth = timeWidth + title.paint.measureText(title.text.toString()) + gap
        val buttonWidth = maxOf(
            extend.paint.measureText(extend.text.toString()) + extend.paddingLeft + extend.paddingRight,
            close.paint.measureText(close.text.toString()) + close.paddingLeft + close.paddingRight,
        )
        return maxOf(
            resources.getDimensionPixelSize(R.dimen.rest_overlay_width),
            ceil(returnWidth + padding * 2).toInt(),
            ceil(buttonWidth * 2 + gap + padding * 2).toInt(),
        )
    }

    private fun timeTextWidth(timer: TextView): Float = maxOf(
        timer.paint.measureText("59:59"),
        timer.paint.measureText(timer.text.toString()),
    )

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
