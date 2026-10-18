package com.teampara.setflow

import android.app.Application
import android.content.Context
import android.graphics.Rect
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.ScrollView
import android.widget.TextView
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowSettings
import org.robolectric.shadows.ShadowWindowManagerImpl
import java.time.Duration
import kotlin.math.roundToInt

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "mdpi")
@LooperMode(LooperMode.Mode.PAUSED)
class RestTimerOverlayTest {
    private lateinit var context: Context
    private lateinit var overlay: RestTimerOverlay
    private var closeCalls = 0
    private var returnCalls = 0
    private var extendCalls = 0

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        ShadowSettings.setCanDrawOverlays(true)
        overlay = RestTimerOverlay(
            context,
            onClose = { closeCalls++ },
            onReturnToWorkout = { returnCalls++ },
            onExtend = { extendCalls++ },
        )
    }

    @After
    fun tearDown() {
        overlay.hide()
        ShadowSettings.setCanDrawOverlays(false)
    }

    @Test
    fun longWorkoutDetailKeepsCompactPanelAndAccessibleContext() {
        val detail = "벤치프레스 100kg × 10회 · 다음은 8세트 · ".repeat(12)
        show(detail = detail)

        val view = overlayView()
        val params = params(view)
        assertTrue("The floating panel must stay narrow", params.width <= dp(192))
        assertTrue("Long detail must not enlarge the panel", params.height <= dp(128))
        assertTrue(view is ScrollView)
        assertTrue(textViews(view).none { it.text.toString() == detail })
        assertTrue(
            view.findViewById<View>(R.id.rest_overlay_return)
                .contentDescription.toString().contains(detail),
        )
        assertEquals("1:30", view.findViewById<TextView>(R.id.rest_overlay_timer).text.toString())
    }

    @Test
    fun controlsKeepAtLeastFortyEightDpTouchTargets() {
        show()
        val view = overlayView()
        for (id in listOf(R.id.rest_overlay_return, R.id.rest_overlay_extend, R.id.rest_overlay_close)) {
            val target = view.findViewById<View>(id)
            assertTrue("Action $id is too narrow", target.width >= dp(48))
            assertTrue("Action $id is too short", target.height >= dp(48))
        }
    }

    @Test
    fun timerAndReturnRowOpenWorkoutWhileButtonsKeepTheirOwnActions() {
        show()
        val view = overlayView()
        val row = view.findViewById<ViewGroup>(R.id.rest_overlay_return)
        row.performClick()
        val timerBounds = timerBounds(row)
        tap(row, timerBounds.exactCenterX(), timerBounds.exactCenterY())
        assertEquals(2, returnCalls)
        assertEquals(0, extendCalls)
        assertEquals(0, closeCalls)

        view.findViewById<View>(R.id.rest_overlay_extend).performClick()
        view.findViewById<View>(R.id.rest_overlay_close).performClick()
        assertEquals(1, extendCalls)
        assertEquals(1, closeCalls)
        assertEquals(2, returnCalls)
    }

    @Test
    fun draggingReturnRowMovesAndClampsWithoutOpeningWorkout() {
        show()
        val view = overlayView()
        val handle = view.findViewById<View>(R.id.rest_overlay_return)
        val initialX = params(view).x
        val initialY = params(view).y

        drag(handle, -10_000f, 10_000f)

        assertTrue(params(view).x < initialX || params(view).y > initialY)
        assertInsideUsableScreen(view)
        assertEquals(0, returnCalls)
        assertEquals(0, closeCalls)
        assertEquals(0, extendCalls)
    }

    @Test
    fun draggingTimerAlsoMovesPanelAndTapReturnsToWorkout() {
        show()
        val view = overlayView()
        val row = view.findViewById<ViewGroup>(R.id.rest_overlay_return)
        val timerBounds = timerBounds(row)
        val initialY = params(view).y

        drag(row, -60f, 80f, timerBounds.exactCenterX(), timerBounds.exactCenterY())

        assertTrue(params(view).y > initialY)
        assertEquals(0, returnCalls)
        tap(row, timerBounds.exactCenterX(), timerBounds.exactCenterY())
        assertEquals(1, returnCalls)
        assertInsideUsableScreen(view)
    }

    @Test
    fun repeatedShowUpdatesCountdownAndContextWithoutAddingAnotherWindow() {
        show(detail = "벤치프레스")
        val firstView = overlayView()
        val firstDeadline = System.currentTimeMillis() + 90_000L

        overlay.show(firstDeadline, "벤치프레스")
        overlay.show(firstDeadline, "벤치프레스")
        overlay.show(System.currentTimeMillis() + 120_000L, "다음은 스쿼트")
        layoutOverlay()

        assertEquals(1, windows().views.size)
        assertSame(firstView, overlayView())
        assertEquals("2:00", firstView.findViewById<TextView>(R.id.rest_overlay_timer).text.toString())
        assertTrue(
            firstView.findViewById<View>(R.id.rest_overlay_return)
                .contentDescription.toString().contains("다음은 스쿼트"),
        )
    }

    @Test
    fun hideRemovesWindowAndPendingTicksAndCanShowAgain() {
        show()
        val firstView = overlayView()
        overlay.hide()
        overlay.hide()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))

        assertTrue(windows().views.isEmpty())
        assertFalse(firstView.isAttachedToWindow)
        assertEquals(0, returnCalls)
        assertEquals(0, closeCalls)
        show()
        assertEquals(1, windows().views.size)
    }

    @Test
    fun windowDoesNotTakeFocusOrBlockTouchesOutsideItsBounds() {
        show()
        val flags = params(overlayView()).flags
        assertTrue(flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0)
        assertTrue(flags and WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL != 0)
        assertFalse(flags and WindowManager.LayoutParams.FLAG_DIM_BEHIND != 0)
    }

    @Test
    @Config(qualifiers = "w220dp-h220dp-mdpi")
    fun largeSystemTextKeepsButtonsReachableByScrollingOnShortScreen() {
        RuntimeEnvironment.setFontScale(2f)
        show(detail = "벤치프레스 100kg × 10회 · 다음은 8세트".repeat(12))
        overlay.show(System.currentTimeMillis() + 3_599_000L, "긴 휴식")
        layoutOverlay()
        val view = overlayView()
        assertTrue(view is ScrollView)
        val scroll = view as ScrollView
        val content = scroll.getChildAt(0)
        assertNotNull(content)
        assertInsideUsableScreen(scroll)
        val timer = scroll.findViewById<TextView>(R.id.rest_overlay_timer)
        assertEquals(2f, timer.context.resources.configuration.fontScale, 0.01f)
        assertTrue("Narrow screen configuration must constrain the window", params(scroll).width <= dp(220))
        assertTrue(
            "Large countdown text must remain fully visible",
            timer.paint.measureText(timer.text.toString()) <= timer.width - timer.paddingLeft - timer.paddingRight,
        )

        for (id in listOf(R.id.rest_overlay_extend, R.id.rest_overlay_close)) {
            val button = scroll.findViewById<View>(id)
            assertTrue(button.width >= dp(48))
            assertTrue(button.height >= dp(48))
            scroll.scrollTo(0, content.height)
            val rect = Rect(0, 0, button.width, button.height)
            scroll.offsetDescendantRectToMyCoords(button, rect)
            assertTrue("Button extends left of viewport: $rect", rect.left >= 0)
            assertTrue("Button extends right of viewport: $rect", rect.right <= scroll.width)
            assertTrue("Button cannot be scrolled fully into view: $rect", rect.top >= 0)
            assertTrue("Button cannot be scrolled fully into view: $rect", rect.bottom <= scroll.height)
        }
        scroll.findViewById<View>(R.id.rest_overlay_extend).performClick()
        scroll.findViewById<View>(R.id.rest_overlay_close).performClick()
        assertEquals(1, extendCalls)
        assertEquals(1, closeCalls)
    }

    private fun show(detail: String = "벤치프레스 · 다음은 2세트") {
        overlay.show(System.currentTimeMillis() + 90_000L, detail)
        shadowOf(Looper.getMainLooper()).idle()
        layoutOverlay()
    }

    private fun layoutOverlay() {
        val view = overlayView()
        val params = params(view)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(params.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(params.height, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, params.width, params.height)
    }

    private fun windows() = Shadow.extract<ShadowWindowManagerImpl>(
        context.getSystemService(WindowManager::class.java),
    )

    private fun overlayView(): View = windows().views.single {
        it.findViewById<View>(R.id.rest_overlay_timer) != null
    }

    private fun params(view: View) = view.layoutParams as WindowManager.LayoutParams

    private fun assertInsideUsableScreen(view: View) {
        val manager = view.context.getSystemService(WindowManager::class.java)
        val metrics = manager.currentWindowMetrics
        val insets = metrics.windowInsets.getInsetsIgnoringVisibility(
            WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
        )
        val width = metrics.bounds.width() - insets.left - insets.right
        val height = metrics.bounds.height() - insets.top - insets.bottom
        val params = params(view)
        assertTrue("Panel starts outside screen", params.x >= 0 && params.y >= 0)
        assertTrue("Panel extends past right edge", params.x + params.width <= width)
        assertTrue("Panel extends past bottom edge", params.y + params.height <= height)
    }

    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).roundToInt()

    private fun textViews(view: View): List<TextView> = when (view) {
        is TextView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { textViews(view.getChildAt(it)) }
        else -> emptyList()
    }

    private fun timerBounds(row: ViewGroup): Rect {
        val timer = row.findViewById<View>(R.id.rest_overlay_timer)
        return Rect(0, 0, timer.width, timer.height).also {
            row.offsetDescendantRectToMyCoords(timer, it)
        }
    }

    private fun drag(view: View, dx: Float, dy: Float, x: Float = 16f, y: Float = 16f) {
        dispatch(view, MotionEvent.ACTION_DOWN, x, y, 0L)
        dispatch(view, MotionEvent.ACTION_MOVE, x + dx, y + dy, 80L)
        dispatch(view, MotionEvent.ACTION_UP, x + dx, y + dy, 120L)
    }

    private fun tap(view: View, x: Float, y: Float) {
        dispatch(view, MotionEvent.ACTION_DOWN, x, y, 0L)
        dispatch(view, MotionEvent.ACTION_UP, x, y, 40L)
    }

    private fun dispatch(view: View, action: Int, x: Float, y: Float, elapsed: Long) {
        val event = MotionEvent.obtain(0L, elapsed, action, x, y, 0)
        try {
            view.dispatchTouchEvent(event)
        } finally {
            event.recycle()
        }
    }
}
