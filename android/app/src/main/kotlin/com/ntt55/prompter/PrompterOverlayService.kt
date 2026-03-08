package com.ntt55.prompter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.NotificationCompat

class PrompterOverlayService : Service() {
    
    private lateinit var windowManager: WindowManager
    private var textOverlayView: View? = null
    private var controlPanelView: View? = null
    private var colorPickerView: View? = null
    
    private var isPlaying = false
        set(value) {
            field = value
            currentlyPlaying = value
        }
    private var scrollSpeed = 50
    private var scrollHandler: Handler? = null
    private var scrollRunnable: Runnable? = null
    private var currentTextColor = Color.BLACK
    
    // Movie Credits mode state
    private var scrollMode = 0 // 0=vertical, 1=movieCredits
    private var movieCreditsOffset = 0f
    private var movieCreditsSingleWidth = 0f  // rendered width of one text copy
    private var movieCreditsLaneWidth = 0     // width of one lane (screen width)
    private var movieCreditsTextViews = mutableListOf<TextView>()
    private var movieCreditsSingleText = ""
    private var currentFontFilePath = ""
    private var pendingInitialProgress = 0.0  // applied once on first scroll frame
    private var skipScrollRestore = false  // when true, updateSettings won't restore scroll position
    
    // Control panel position for dragging
    private var controlX = 0
    private var controlY = 0
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    
    companion object {
        const val CHANNEL_ID = "prompter_overlay_channel"
        const val NOTIFICATION_ID = 1001
        
        const val ACTION_SHOW = "com.example.prompter.SHOW"
        const val ACTION_HIDE = "com.example.prompter.HIDE"
        const val ACTION_UPDATE_TEXT = "com.example.prompter.UPDATE_TEXT"
        const val ACTION_UPDATE_SETTINGS = "com.example.prompter.UPDATE_SETTINGS"
        const val ACTION_PLAY_PAUSE = "com.example.prompter.PLAY_PAUSE"
        const val ACTION_SPEED_UP = "com.example.prompter.SPEED_UP"
        const val ACTION_SPEED_DOWN = "com.example.prompter.SPEED_DOWN"
        const val ACTION_SCROLL_UP = "com.example.prompter.SCROLL_UP"
        const val ACTION_SCROLL_DOWN = "com.example.prompter.SCROLL_DOWN"
        const val ACTION_RESET_TO_START = "com.example.prompter.RESET_TO_START"
        
        const val EXTRA_TEXT = "text"
        const val EXTRA_FONT_SIZE = "fontSize"
        const val EXTRA_TEXT_COLOR = "textColor"
        const val EXTRA_BG_COLOR = "backgroundColor"
        const val EXTRA_SPEED = "speed"
        const val EXTRA_MIRROR = "mirrorHorizontal"
        const val EXTRA_FONT_FAMILY = "fontFamily"
        const val EXTRA_IS_BOLD = "isBold"
        const val EXTRA_IS_ITALIC = "isItalic"
        const val EXTRA_LINE_HEIGHT = "lineHeight"
        const val EXTRA_TEXT_ALIGN = "textAlign"
        const val EXTRA_OPACITY = "opacity"
        const val EXTRA_PADDING_H = "paddingHorizontal"
        const val EXTRA_OVERLAY_POS = "overlayPosition"
        const val EXTRA_OVERLAY_HEIGHT = "overlayHeight"
        const val EXTRA_SCROLL_MODE = "scrollMode"
        const val EXTRA_FONT_FILE_PATH = "fontFilePath"
        const val EXTRA_INITIAL_PROGRESS = "initialProgress"
        
        // Static state for overlay→app sync
        var isRunning = false
            private set
        var currentSpeed = 50
            private set
        var currentColor = Color.BLACK
            private set
        var currentlyPlaying = false
            private set
        var currentScrollProgress = 0.0
            private set
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        scrollHandler = Handler(Looper.getMainLooper())
        createNotificationChannel()
    }

    /// Resolve a Typeface: prefer loading from a downloaded TTF file path,
    /// fall back to system font family name.
    private fun resolveTypeface(fontFilePath: String, fontFamily: String, typefaceStyle: Int): android.graphics.Typeface {
        // Try loading from file first
        if (fontFilePath.isNotEmpty()) {
            try {
                val file = java.io.File(fontFilePath)
                if (file.exists() && file.length() > 0) {
                    val base = android.graphics.Typeface.createFromFile(file)
                    return android.graphics.Typeface.create(base, typefaceStyle)
                }
            } catch (_: Exception) {}
        }
        // Map common font names to Android system font families
        val androidFamily = when (fontFamily.lowercase()) {
            "times new roman", "times", "georgia", "playfair display", "merriweather" -> "serif"
            "arial", "helvetica", "verdana" -> "sans-serif"
            "courier new", "courier" -> "monospace"
            else -> fontFamily
        }
        return try {
            android.graphics.Typeface.create(androidFamily, typefaceStyle)
        } catch (_: Exception) {
            android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, typefaceStyle)
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val text = intent.getStringExtra(EXTRA_TEXT) ?: "No text"
                val fontSize = intent.getFloatExtra(EXTRA_FONT_SIZE, 24f)
                val textColor = intent.getIntExtra(EXTRA_TEXT_COLOR, Color.BLACK)
                val bgColor = intent.getIntExtra(EXTRA_BG_COLOR, Color.TRANSPARENT)
                scrollSpeed = intent.getIntExtra(EXTRA_SPEED, 50)
                val mirror = intent.getBooleanExtra(EXTRA_MIRROR, false)
                val fontFamily = intent.getStringExtra(EXTRA_FONT_FAMILY) ?: "Roboto"
                val isBold = intent.getBooleanExtra(EXTRA_IS_BOLD, false)
                val isItalic = intent.getBooleanExtra(EXTRA_IS_ITALIC, false)
                val lineHeight = intent.getFloatExtra(EXTRA_LINE_HEIGHT, 1.5f)
                val textAlign = intent.getIntExtra(EXTRA_TEXT_ALIGN, 1)
                val opacity = intent.getFloatExtra(EXTRA_OPACITY, 0f)
                val paddingH = intent.getFloatExtra(EXTRA_PADDING_H, 20f)
                val overlayPos = intent.getIntExtra(EXTRA_OVERLAY_POS, 2)
                val overlayHeight = intent.getFloatExtra(EXTRA_OVERLAY_HEIGHT, 150f)
                val scrollModeVal = intent.getIntExtra(EXTRA_SCROLL_MODE, 0)
                currentTextColor = textColor
                isRunning = true
                currentSpeed = scrollSpeed
                currentColor = textColor
                scrollMode = scrollModeVal
                currentFontFilePath = intent.getStringExtra(EXTRA_FONT_FILE_PATH) ?: ""
                pendingInitialProgress = intent.getDoubleExtra(EXTRA_INITIAL_PROGRESS, 0.0)
                showOverlay(text, fontSize, textColor, bgColor, mirror, fontFamily, isBold, isItalic, lineHeight, textAlign, opacity, paddingH, overlayPos, overlayHeight, scrollModeVal)
                startForeground(NOTIFICATION_ID, createNotification())
            }
            ACTION_UPDATE_SETTINGS -> {
                val text = intent.getStringExtra(EXTRA_TEXT) ?: "No text"
                val fontSize = intent.getFloatExtra(EXTRA_FONT_SIZE, 24f)
                val textColor = intent.getIntExtra(EXTRA_TEXT_COLOR, Color.BLACK)
                val bgColor = intent.getIntExtra(EXTRA_BG_COLOR, Color.TRANSPARENT)
                val newSpeed = intent.getIntExtra(EXTRA_SPEED, 50)
                val mirror = intent.getBooleanExtra(EXTRA_MIRROR, false)
                val fontFamily = intent.getStringExtra(EXTRA_FONT_FAMILY) ?: "Roboto"
                val isBold = intent.getBooleanExtra(EXTRA_IS_BOLD, false)
                val isItalic = intent.getBooleanExtra(EXTRA_IS_ITALIC, false)
                val lineHeight = intent.getFloatExtra(EXTRA_LINE_HEIGHT, 1.5f)
                val textAlign = intent.getIntExtra(EXTRA_TEXT_ALIGN, 1)
                val opacity = intent.getFloatExtra(EXTRA_OPACITY, 0f)
                val paddingH = intent.getFloatExtra(EXTRA_PADDING_H, 20f)
                val overlayPos = intent.getIntExtra(EXTRA_OVERLAY_POS, 2)
                val overlayHeight = intent.getFloatExtra(EXTRA_OVERLAY_HEIGHT, 150f)
                val scrollModeVal = intent.getIntExtra(EXTRA_SCROLL_MODE, 0)

                scrollSpeed = newSpeed
                currentSpeed = newSpeed
                currentTextColor = textColor
                currentColor = textColor
                currentFontFilePath = intent.getStringExtra(EXTRA_FONT_FILE_PATH) ?: ""

                // Only do a full rebuild if scroll mode changed or views don't exist yet
                val needsRebuild = scrollModeVal != scrollMode || textOverlayView == null

                if (needsRebuild) {
                    val savedScroll = if (skipScrollRestore) 0f else if (scrollMode == 1) movieCreditsOffset else (textOverlayView as? ScrollView)?.scrollY?.toFloat() ?: 0f
                    val wasPlaying = isPlaying
                    scrollMode = scrollModeVal
                    hideOverlay()
                    showOverlay(text, fontSize, textColor, bgColor, mirror, fontFamily, isBold, isItalic, lineHeight, textAlign, opacity, paddingH, overlayPos, overlayHeight, scrollModeVal)
                    if (!skipScrollRestore) {
                        if (scrollMode == 1) {
                            movieCreditsOffset = savedScroll
                        } else {
                            (textOverlayView as? ScrollView)?.post {
                                (textOverlayView as? ScrollView)?.scrollTo(0, savedScroll.toInt())
                            }
                        }
                    }
                    skipScrollRestore = false
                    if (!wasPlaying) {
                        stopScrolling()
                        isPlaying = false
                        controlPanelView?.findViewWithTag<TextView>("playPauseBtn")?.text = "▶"
                    }
                } else {
                    // In-place update — no rebuild, no jitter
                    scrollMode = scrollModeVal
                    val density = resources.displayMetrics.density
                    val paddingPx = (paddingH * density).toInt()
                    val vertPadding = (16 * density).toInt()

                    // Background color with opacity
                    val bgR = Color.red(bgColor)
                    val bgG = Color.green(bgColor)
                    val bgB = Color.blue(bgColor)
                    val bgAlpha = (opacity * 255).toInt().coerceIn(0, 255)
                    val finalBgColor = Color.argb(bgAlpha, bgR, bgG, bgB)

                    // Typeface
                    val typefaceStyle = when {
                        isBold && isItalic -> android.graphics.Typeface.BOLD_ITALIC
                        isBold -> android.graphics.Typeface.BOLD
                        isItalic -> android.graphics.Typeface.ITALIC
                        else -> android.graphics.Typeface.NORMAL
                    }
                    val typeface = resolveTypeface(currentFontFilePath, fontFamily, typefaceStyle)

                    val gravityAlign = when (textAlign) {
                        0 -> Gravity.START
                        1 -> Gravity.END
                        2 -> Gravity.CENTER_HORIZONTAL
                        3 -> Gravity.CENTER_HORIZONTAL
                        else -> Gravity.CENTER_HORIZONTAL
                    }

                    val shadowColor = if (textColor == Color.WHITE || textColor == Color.YELLOW) Color.BLACK else Color.WHITE

                    if (scrollMode == 1) {
                        // Movie credits — update existing text views and lane sizes
                        val singleLineH = measureSingleLineHeight(fontSize, lineHeight, isBold, isItalic, fontFamily)
                        val laneStride = (singleLineH * lineHeight).toInt()
                        for ((i, tv) in movieCreditsTextViews.withIndex()) {
                            tv.textSize = fontSize
                            tv.setTextColor(textColor)
                            tv.typeface = typeface
                            tv.setShadowLayer(4f, 2f, 2f, shadowColor)
                            // Update the lane (parent) height and position
                            (tv.parent as? android.widget.FrameLayout)?.let { lane ->
                                lane.setPadding(paddingPx, 0, paddingPx, 0)
                                val lp = lane.layoutParams as android.widget.FrameLayout.LayoutParams
                                lp.height = singleLineH
                                lp.topMargin = i * laneStride
                                lane.layoutParams = lp
                            }
                        }
                        textOverlayView?.setBackgroundColor(finalBgColor)
                        textOverlayView?.scaleX = if (mirror) -1f else 1f
                        updateText(text)
                    } else {
                        // Vertical mode — update ScrollView + TextView in-place
                        val scrollView = textOverlayView as? ScrollView
                        val textView = scrollView?.tag as? TextView

                        if (textView != null && scrollView != null) {
                            // Save scroll position before property changes
                            val savedScrollY = scrollView.scrollY

                            // Batch all property updates, then single relayout
                            textView.textSize = fontSize
                            textView.setTextColor(textColor)
                            textView.typeface = typeface
                            textView.setLineSpacing(0f, lineHeight)
                            textView.gravity = gravityAlign
                            textView.setPadding(paddingPx, vertPadding, paddingPx, vertPadding)
                            textView.setShadowLayer(4f, 2f, 2f, shadowColor)
                            textView.text = text

                            scrollView.setBackgroundColor(finalBgColor)
                            scrollView.scaleX = if (mirror) -1f else 1f

                            // Restore scroll position after layout completes
                            scrollView.post {
                                if (skipScrollRestore) {
                                    scrollView.scrollTo(0, 0)
                                    currentScrollProgress = 0.0
                                    skipScrollRestore = false
                                } else {
                                    val maxScroll = (scrollView.getChildAt(0)?.height ?: 0) - scrollView.height
                                    scrollView.scrollTo(0, savedScrollY.coerceIn(0, maxScroll.coerceAtLeast(0)))
                                }
                            }
                        }
                    }

                    // Update overlay position and height via WindowManager (no rebuild)
                    textOverlayView?.let { view ->
                        try {
                            val params = view.layoutParams as WindowManager.LayoutParams
                            val posGravity = when (overlayPos) {
                                0 -> Gravity.TOP
                                1 -> Gravity.CENTER_VERTICAL
                                else -> Gravity.BOTTOM
                            }
                            params.gravity = posGravity or Gravity.CENTER_HORIZONTAL

                            val heightPx = (overlayHeight * density).toInt()
                            params.height = heightPx

                            windowManager.updateViewLayout(view, params)
                        } catch (e: Exception) {
                            // View might not be attached
                        }
                    }
                }
            }
            ACTION_HIDE -> {
                isRunning = false
                hideOverlay()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_UPDATE_TEXT -> {
                val text = intent.getStringExtra(EXTRA_TEXT) ?: return START_STICKY
                updateText(text)
            }
            ACTION_PLAY_PAUSE -> togglePlayPause()
            ACTION_SPEED_UP -> speedUp()
            ACTION_SPEED_DOWN -> speedDown()
            ACTION_SCROLL_UP -> scrollUp()
            ACTION_SCROLL_DOWN -> scrollDown()
            ACTION_RESET_TO_START -> resetToStart()
        }
        return START_STICKY
    }
    
    private fun showOverlay(
        text: String, fontSize: Float, textColor: Int, bgColor: Int = Color.TRANSPARENT,
        mirror: Boolean = false, fontFamily: String = "Roboto",
        isBold: Boolean = false, isItalic: Boolean = false,
        lineHeight: Float = 1.5f, textAlign: Int = 1,
        opacity: Float = 0f, paddingH: Float = 20f,
        overlayPos: Int = 2, overlayHeight: Float = 150f,
        scrollModeParam: Int = 0
    ) {
        if (textOverlayView != null) return
        
        val density = resources.displayMetrics.density
        
        val heightPx = (overlayHeight * density).toInt()
        
        // === Layer 1: Text Overlay (Click-through) ===
        if (scrollModeParam == 1) {
            textOverlayView = createMovieCreditsView(
                text, fontSize, textColor, bgColor, mirror, fontFamily,
                isBold, isItalic, lineHeight, textAlign, opacity, paddingH, heightPx
            )
        } else {
            textOverlayView = createTextOverlayView(
                text, fontSize, textColor, bgColor, mirror, fontFamily,
                isBold, isItalic, lineHeight, textAlign, opacity, paddingH
            )
        }
        
        // Overlay position gravity
        val posGravity = when (overlayPos) {
            0 -> Gravity.TOP      // top
            1 -> Gravity.CENTER_VERTICAL  // center
            else -> Gravity.BOTTOM // bottom (default)
        }
        
        val textParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            heightPx,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) 
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 
            else 
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        textParams.gravity = posGravity or Gravity.CENTER_HORIZONTAL
        
        windowManager.addView(textOverlayView, textParams)
        
        // === Layer 2: Control Panel (Touchable) ===
        controlPanelView = createControlPanelView()
        
        val controlParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) 
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 
            else 
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,  // Touchable!
            PixelFormat.TRANSLUCENT
        )
        controlParams.gravity = Gravity.TOP or Gravity.START
        controlParams.x = 50
        controlParams.y = 300
        controlX = controlParams.x
        controlY = controlParams.y
        
        windowManager.addView(controlPanelView, controlParams)
        
        // Start auto-scroll
        startScrolling()
    }
    
    private fun createTextOverlayView(
        text: String, fontSize: Float, textColor: Int, bgColor: Int = Color.TRANSPARENT,
        mirror: Boolean = false, fontFamily: String = "Roboto",
        isBold: Boolean = false, isItalic: Boolean = false,
        lineHeight: Float = 1.5f, textAlign: Int = 1,
        opacity: Float = 0f, paddingH: Float = 20f
    ): View {
        val density = resources.displayMetrics.density
        val paddingPx = (paddingH * density).toInt()
        val vertPadding = (16 * density).toInt()
        
        // Calculate background color with opacity
        val bgR = Color.red(bgColor)
        val bgG = Color.green(bgColor)
        val bgB = Color.blue(bgColor)
        val bgAlpha = (opacity * 255).toInt().coerceIn(0, 255)
        val finalBgColor = Color.argb(bgAlpha, bgR, bgG, bgB)
        
        // Map textAlign: Flutter TextAlign enum indices
        // 0=left, 1=right, 2=center, 3=justify, 4=start, 5=end
        val gravityAlign = when (textAlign) {
            0 -> Gravity.START
            1 -> Gravity.END
            2 -> Gravity.CENTER_HORIZONTAL
            3 -> Gravity.CENTER_HORIZONTAL
            else -> Gravity.CENTER_HORIZONTAL
        }
        
        // Typeface: bold/italic
        val typefaceStyle = when {
            isBold && isItalic -> android.graphics.Typeface.BOLD_ITALIC
            isBold -> android.graphics.Typeface.BOLD
            isItalic -> android.graphics.Typeface.ITALIC
            else -> android.graphics.Typeface.NORMAL
        }
        
        // Font family typeface
        val typeface = resolveTypeface(currentFontFilePath, fontFamily, typefaceStyle)
        
        val scrollView = ScrollView(this).apply {
            id = View.generateViewId()
            setBackgroundColor(finalBgColor)
            isVerticalScrollBarEnabled = false
            isFillViewport = true
            if (mirror) {
                scaleX = -1f
            }
        }
        
        val textView = TextView(this).apply {
            this.text = text
            this.textSize = fontSize
            this.setTextColor(textColor)
            this.typeface = typeface
            this.setPadding(paddingPx, vertPadding, paddingPx, vertPadding)
            this.gravity = gravityAlign
            this.setLineSpacing(0f, lineHeight)
            // Shadow for visibility
            val shadowColor = if (textColor == Color.WHITE || textColor == Color.YELLOW) Color.BLACK else Color.WHITE
            this.setShadowLayer(4f, 2f, 2f, shadowColor)
        }
        
        scrollView.addView(textView)
        scrollView.tag = textView
        
        return scrollView
    }
    
    private fun createControlPanelView(): View {
        val context = this
        
        // Main container with rounded background
        val container = android.widget.LinearLayout(context).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setBackgroundColor(Color.argb(200, 40, 40, 40))
            setPadding(12, 12, 12, 12)
        }
        
        // Button size - smaller
        val btnSize = 36
        val iconSize = 20
        
        // Scroll Up button
        val btnUp = createControlButton(context, "▲", btnSize) { scrollUp() }
        container.addView(btnUp)
        
        // Speed Down button
        val btnSlower = createControlButton(context, "−", btnSize) { speedDown() }
        container.addView(btnSlower)
        
        // Play/Pause button
        val btnPlayPause = createControlButton(context, "▶", btnSize) { 
            togglePlayPause()
            (it as? TextView)?.text = if (isPlaying) "⏸" else "▶"
        }
        btnPlayPause.tag = "playPauseBtn"
        container.addView(btnPlayPause)
        
        // Speed Up button
        val btnFaster = createControlButton(context, "+", btnSize) { speedUp() }
        container.addView(btnFaster)
        
        // Scroll Down button
        val btnDown = createControlButton(context, "▼", btnSize) { scrollDown() }
        container.addView(btnDown)
        
        // Color picker button - opens popup
        val btnColor = createControlButton(context, "🎨", btnSize) { 
            showColorPickerPopup()
        }
        btnColor.tag = "colorBtn"
        container.addView(btnColor)
        
        // Close button
        val btnClose = createControlButton(context, "✕", btnSize, Color.RED) { 
            sendBroadcast(Intent(ACTION_HIDE).setPackage(packageName))
            hideOverlay()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        container.addView(btnClose)
        
        // Make control panel draggable
        setupDraggable(container)
        
        return container
    }
    
    private fun createControlButton(
        context: Context, 
        text: String, 
        size: Int, 
        bgColor: Int = Color.argb(180, 80, 80, 80),
        onClick: (View) -> Unit
    ): TextView {
        return TextView(context).apply {
            this.text = text
            this.textSize = 14f
            this.setTextColor(Color.WHITE)
            this.gravity = Gravity.CENTER
            this.setBackgroundColor(bgColor)
            this.setPadding(8, 8, 8, 8)
            
            val params = android.widget.LinearLayout.LayoutParams(
                (size * resources.displayMetrics.density).toInt(),
                (size * resources.displayMetrics.density).toInt()
            )
            params.setMargins(0, 4, 0, 4)
            this.layoutParams = params
            
            this.setOnClickListener { onClick(it) }
        }
    }
    
    private fun setupDraggable(view: View) {
        view.setOnTouchListener { v, event ->
            val params = v.layoutParams as WindowManager.LayoutParams
            
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - initialTouchX).toInt()
                    params.y = initialY + (event.rawY - initialTouchY).toInt()
                    controlX = params.x
                    controlY = params.y
                    windowManager.updateViewLayout(v, params)
                    true
                }
                else -> false
            }
        }
    }
    
    private fun hideOverlay() {
        stopScrolling()
        hideColorPickerPopup()
        movieCreditsTextViews.clear()
        
        textOverlayView?.let {
            try { windowManager.removeView(it) } catch (e: Exception) {}
        }
        controlPanelView?.let {
            try { windowManager.removeView(it) } catch (e: Exception) {}
        }
        
        textOverlayView = null
        controlPanelView = null
    }
    
    private fun updateText(text: String) {
        if (scrollMode == 1) {
            // Movie credits: update single-line text and re-measure
            movieCreditsSingleText = text.replace("\n", "     ") + "     "
            if (movieCreditsTextViews.isNotEmpty()) {
                val scaledDensity = resources.displayMetrics.scaledDensity
                val paint = movieCreditsTextViews[0].paint
                movieCreditsSingleWidth = paint.measureText(movieCreditsSingleText)
                val repeatedText = buildRepeatedMovieCreditsText(movieCreditsSingleText, movieCreditsSingleWidth)
                val repeatedWidth = (paint.measureText(repeatedText) + 1).toInt()
                for (tv in movieCreditsTextViews) {
                    tv.text = repeatedText
                    tv.layoutParams.width = repeatedWidth
                    tv.requestLayout()
                }
            }
        } else {
            (textOverlayView as? ScrollView)?.let { scrollView ->
                (scrollView.tag as? TextView)?.text = text
            }
        }
    }
    
    private fun togglePlayPause() {
        isPlaying = !isPlaying
        if (isPlaying) {
            startScrolling()
        } else {
            stopScrolling()
        }
        
        // Update button text
        controlPanelView?.findViewWithTag<TextView>("playPauseBtn")?.text = 
            if (isPlaying) "⏸" else "▶"
    }
    
    private fun startScrolling() {
        isPlaying = true
        if (scrollMode == 1) {
            startMovieCreditsScrolling()
        } else {
            startRegularScrolling()
        }
    }
    
    private fun startRegularScrolling() {
        // If already at end, reset to beginning before starting
        (textOverlayView as? ScrollView)?.let { scrollView ->
            val currentY = scrollView.scrollY
            val maxY = scrollView.getChildAt(0)?.height?.minus(scrollView.height) ?: 0
            if (maxY > 0 && currentY >= maxY) {
                scrollView.scrollTo(0, 0)
                currentScrollProgress = 0.0
            }
        }
        scrollRunnable = object : Runnable {
            private var appliedInitial = false
            override fun run() {
                if (isPlaying) {
                    (textOverlayView as? ScrollView)?.let { scrollView ->
                        val currentY = scrollView.scrollY
                        val maxY = scrollView.getChildAt(0)?.height?.minus(scrollView.height) ?: 0

                        // Apply initial progress on first frame with valid layout
                        if (!appliedInitial && pendingInitialProgress > 0.0 && maxY > 0) {
                            val targetY = (maxY * pendingInitialProgress).toInt().coerceIn(0, maxY)
                            scrollView.scrollTo(0, targetY)
                            pendingInitialProgress = 0.0
                            appliedInitial = true
                            currentScrollProgress = targetY.toDouble() / maxY.toDouble()
                            scrollHandler?.postDelayed(this, 33L)
                            return
                        }
                        appliedInitial = true
                        
                        // Update scroll progress for app sync
                        currentScrollProgress = if (maxY > 0) currentY.toDouble() / maxY.toDouble() else 0.0

                        if (currentY < maxY) {
                            val scrollStep = (scrollSpeed / 20).coerceIn(1, 15)
                            scrollView.scrollBy(0, scrollStep)
                        } else {
                            currentScrollProgress = 1.0
                            isPlaying = false
                            controlPanelView?.findViewWithTag<TextView>("playPauseBtn")?.text = "▶"
                            return
                        }
                    }
                    scrollHandler?.postDelayed(this, 33L)
                }
            }
        }
        scrollHandler?.post(scrollRunnable!!)
    }
    
    private fun startMovieCreditsScrolling() {
        // Apply initial progress for movie credits
        if (pendingInitialProgress > 0.0 && movieCreditsSingleWidth > 0) {
            movieCreditsOffset = (movieCreditsSingleWidth * pendingInitialProgress).toFloat()
            pendingInitialProgress = 0.0
        }
        scrollRunnable = object : Runnable {
            override fun run() {
                if (isPlaying) {
                    if (movieCreditsSingleWidth > 0) {
                        movieCreditsOffset += scrollSpeed / 30f
                        if (movieCreditsOffset >= movieCreditsSingleWidth) {
                            movieCreditsOffset -= movieCreditsSingleWidth
                        }
                        // Update scroll progress for app sync
                        currentScrollProgress = movieCreditsOffset.toDouble() / movieCreditsSingleWidth.toDouble()
                        updateMovieCreditsPositions()
                    }
                    scrollHandler?.postDelayed(this, 33L)
                }
            }
        }
        scrollHandler?.post(scrollRunnable!!)
    }
    
    private fun updateMovieCreditsPositions() {
        if (movieCreditsSingleWidth <= 0 || movieCreditsLaneWidth <= 0) return
        val effectiveOffset = movieCreditsOffset % movieCreditsSingleWidth
        for (i in movieCreditsTextViews.indices) {
            // i=0 is top (line 1, oldest), i=2 is bottom (line 3, newest)
            // Single text flows: line 1 → line 2 → line 3
            val lineOffset = effectiveOffset + i * movieCreditsLaneWidth
            movieCreditsTextViews[i].translationX = -lineOffset
        }
    }
    
    private fun stopScrolling() {
        scrollRunnable?.let { scrollHandler?.removeCallbacks(it) }
    }
    
    private fun speedUp() {
        scrollSpeed = (scrollSpeed + 20).coerceAtMost(300)
        currentSpeed = scrollSpeed
    }
    
    private fun speedDown() {
        scrollSpeed = (scrollSpeed - 20).coerceAtLeast(20)
        currentSpeed = scrollSpeed
    }
    
    private fun scrollUp() {
        if (scrollMode == 1) {
            // Reverse scroll (go backward)
            movieCreditsOffset = (movieCreditsOffset - 200f)
            if (movieCreditsOffset < 0 && movieCreditsSingleWidth > 0) {
                movieCreditsOffset += movieCreditsSingleWidth
            }
            updateMovieCreditsPositions()
        } else {
            (textOverlayView as? ScrollView)?.smoothScrollBy(0, -200)
        }
    }
    
    private fun scrollDown() {
        if (scrollMode == 1) {
            // Advance scroll (go forward)
            movieCreditsOffset += 200f
            if (movieCreditsSingleWidth > 0 && movieCreditsOffset >= movieCreditsSingleWidth) {
                movieCreditsOffset -= movieCreditsSingleWidth
            }
            updateMovieCreditsPositions()
        } else {
            (textOverlayView as? ScrollView)?.smoothScrollBy(0, 200)
        }
    }

    private fun resetToStart() {
        skipScrollRestore = true
        if (scrollMode == 1) {
            movieCreditsOffset = 0f
            updateMovieCreditsPositions()
        } else {
            (textOverlayView as? ScrollView)?.scrollTo(0, 0)
        }
        currentScrollProgress = 0.0
    }
    
    private fun changeTextColor(color: Int) {
        currentTextColor = color
        currentColor = color
        if (scrollMode == 1) {
            val shadowColor = if (color == Color.WHITE || color == Color.YELLOW) Color.BLACK else Color.WHITE
            for (tv in movieCreditsTextViews) {
                tv.setTextColor(color)
                tv.setShadowLayer(4f, 2f, 2f, shadowColor)
            }
        } else {
            (textOverlayView as? ScrollView)?.let { scrollView ->
                (scrollView.tag as? TextView)?.setTextColor(color)
                val shadowColor = if (color == Color.WHITE || color == Color.YELLOW) Color.BLACK else Color.WHITE
                (scrollView.tag as? TextView)?.setShadowLayer(4f, 2f, 2f, shadowColor)
            }
        }
        // Close color picker popup
        hideColorPickerPopup()
    }
    
    private fun showColorPickerPopup() {
        if (colorPickerView != null) {
            hideColorPickerPopup()
            return
        }
        
        val context = this
        val colors = listOf(
            Pair(Color.WHITE, "Trắng"),
            Pair(Color.YELLOW, "Vàng"),
            Pair(Color.GREEN, "Xanh lá"),
            Pair(Color.CYAN, "Xanh dương"),
            Pair(Color.RED, "Đỏ"),
            Pair(Color.MAGENTA, "Hồng"),
            Pair(Color.BLACK, "Đen"),
            Pair(Color.rgb(255, 165, 0), "Cam")
        )
        
        val container = android.widget.LinearLayout(context).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setBackgroundColor(Color.argb(230, 50, 50, 50))
            setPadding(24, 24, 24, 24)
        }
        
        // Title
        val title = TextView(context).apply {
            text = "Chọn màu chữ"
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
        }
        container.addView(title)
        
        // Color grid (2 columns)
        val grid = android.widget.GridLayout(context).apply {
            columnCount = 2
            rowCount = 4
        }
        
        val btnSize = 80
        for ((color, name) in colors) {
            val colorBtn = android.widget.LinearLayout(context).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(12, 12, 12, 12)
                setBackgroundColor(Color.argb(100, 80, 80, 80))
                
                val params = android.widget.GridLayout.LayoutParams().apply {
                    width = (btnSize * resources.displayMetrics.density).toInt()
                    height = (btnSize * resources.displayMetrics.density).toInt()
                    setMargins(8, 8, 8, 8)
                }
                layoutParams = params
                
                // Color circle
                val circle = TextView(context).apply {
                    text = "●"
                    textSize = 36f
                    setTextColor(color)
                    gravity = Gravity.CENTER
                }
                addView(circle)
                
                // Color name
                val label = TextView(context).apply {
                    text = name
                    textSize = 10f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                }
                addView(label)
                
                setOnClickListener { changeTextColor(color) }
            }
            grid.addView(colorBtn)
        }
        container.addView(grid)
        
        // Close button
        val closeBtn = TextView(context).apply {
            text = "Đóng"
            textSize = 14f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.argb(180, 100, 100, 100))
            gravity = Gravity.CENTER
            setPadding(24, 16, 24, 16)
            val params = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.setMargins(0, 16, 0, 0)
            layoutParams = params
            setOnClickListener { hideColorPickerPopup() }
        }
        container.addView(closeBtn)
        
        colorPickerView = container
        
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) 
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 
            else 
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER
        
        windowManager.addView(colorPickerView, params)
    }
    
    private fun hideColorPickerPopup() {
        colorPickerView?.let {
            try { windowManager.removeView(it) } catch (e: Exception) {}
        }
        colorPickerView = null
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Prompter Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Hiển thị khi prompter đang chạy"
                setShowBadge(false)
            }
            
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, 
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Prompter đang chạy")
            .setContentText("Nhấn để mở app")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
    
    // ============ Movie Credits Mode ============
    
    private fun calculateThreeLineHeight(
        fontSize: Float, lineHeight: Float,
        isBold: Boolean, isItalic: Boolean, fontFamily: String,
        paddingH: Float = 0f
    ): Int {
        val density = resources.displayMetrics.density
        val typefaceStyle = when {
            isBold && isItalic -> android.graphics.Typeface.BOLD_ITALIC
            isBold -> android.graphics.Typeface.BOLD
            isItalic -> android.graphics.Typeface.ITALIC
            else -> android.graphics.Typeface.NORMAL
        }
        val typeface = resolveTypeface(currentFontFilePath, fontFamily, typefaceStyle)
        val paddingPx = (paddingH * density).toInt()
        val vertPadding = (16 * density).toInt()
        val widthSpec = View.MeasureSpec.makeMeasureSpec(
            resources.displayMetrics.widthPixels,
            View.MeasureSpec.AT_MOST
        )
        val unspecHeight = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)

        // Measure 3 lines with line spacing (includes trailing space after line 3)
        val tv3 = TextView(this).apply {
            text = "Ag\nAg\nAg"
            textSize = fontSize
            this.typeface = typeface
            setLineSpacing(0f, lineHeight)
            setPadding(paddingPx, vertPadding, paddingPx, vertPadding)
        }
        tv3.measure(widthSpec, unspecHeight)

        // Measure 1 line with and without spacing to find the trailing space.
        // Android applies the lineHeight multiplier to every line INCLUDING the last,
        // so we subtract the trailing portion so spacing only appears BETWEEN lines.
        val tv1Spaced = TextView(this).apply {
            text = "Ag"
            textSize = fontSize
            this.typeface = typeface
            setLineSpacing(0f, lineHeight)
            setPadding(0, 0, 0, 0)
        }
        tv1Spaced.measure(widthSpec, unspecHeight)

        val tv1Normal = TextView(this).apply {
            text = "Ag"
            textSize = fontSize
            this.typeface = typeface
            setLineSpacing(0f, 1.0f)
            setPadding(0, 0, 0, 0)
        }
        tv1Normal.measure(widthSpec, unspecHeight)

        val trailing = tv1Spaced.measuredHeight - tv1Normal.measuredHeight
        return tv3.measuredHeight - trailing
    }
    
    private fun buildRepeatedMovieCreditsText(singleLineText: String, singleWidth: Float): String {
        val screenWidth = resources.displayMetrics.widthPixels.toFloat()
        // Need enough copies to fill 3 lines (3 * screenWidth) for continuous flow
        val copies = if (singleWidth > 0) {
            ((3 * screenWidth) / singleWidth).toInt() + 3
        } else 5
        return singleLineText.repeat(copies.coerceIn(3, 50))
    }
    
    private fun measureSingleLineHeight(
        fontSize: Float, lineHeight: Float,
        isBold: Boolean, isItalic: Boolean, fontFamily: String
    ): Int {
        val typefaceStyle = when {
            isBold && isItalic -> android.graphics.Typeface.BOLD_ITALIC
            isBold -> android.graphics.Typeface.BOLD
            isItalic -> android.graphics.Typeface.ITALIC
            else -> android.graphics.Typeface.NORMAL
        }
        val typeface = resolveTypeface(currentFontFilePath, fontFamily, typefaceStyle)
        val tempTv = TextView(this).apply {
            text = "Ag"
            textSize = fontSize
            this.typeface = typeface
            setLineSpacing(0f, lineHeight)
            setSingleLine(true)
            maxLines = 1
        }
        val widthSpec = View.MeasureSpec.makeMeasureSpec(
            resources.displayMetrics.widthPixels,
            View.MeasureSpec.AT_MOST
        )
        tempTv.measure(widthSpec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        return tempTv.measuredHeight
    }
    
    private fun createMovieCreditsView(
        text: String, fontSize: Float, textColor: Int, bgColor: Int = Color.TRANSPARENT,
        mirror: Boolean = false, fontFamily: String = "Roboto",
        isBold: Boolean = false, isItalic: Boolean = false,
        lineHeight: Float = 1.5f, textAlign: Int = 1,
        opacity: Float = 0f, paddingH: Float = 20f,
        overlayHeightPx: Int = 0
    ): View {
        val density = resources.displayMetrics.density
        val paddingPx = (paddingH * density).toInt()
        
        val bgR = Color.red(bgColor)
        val bgG = Color.green(bgColor)
        val bgB = Color.blue(bgColor)
        val bgAlpha = (opacity * 255).toInt().coerceIn(0, 255)
        val finalBgColor = Color.argb(bgAlpha, bgR, bgG, bgB)
        
        val typefaceStyle = when {
            isBold && isItalic -> android.graphics.Typeface.BOLD_ITALIC
            isBold -> android.graphics.Typeface.BOLD
            isItalic -> android.graphics.Typeface.ITALIC
            else -> android.graphics.Typeface.NORMAL
        }
        val typeface = resolveTypeface(currentFontFilePath, fontFamily, typefaceStyle)
        
        val shadowColor = if (textColor == Color.WHITE || textColor == Color.YELLOW) Color.BLACK else Color.WHITE
        
        // Prepare single-line text
        movieCreditsSingleText = text.replace("\n", "     ") + "     "
        
        // Pre-measure text width using Paint (avoids layout dependency)
        val scaledDensity = resources.displayMetrics.scaledDensity
        val measurePaint = android.graphics.Paint().apply {
            textSize = fontSize * scaledDensity
            this.typeface = typeface
        }
        val singleTextWidth = measurePaint.measureText(movieCreditsSingleText)
        val screenWidth = resources.displayMetrics.widthPixels.toFloat()
        
        // Set dimensions immediately (no need to wait for layout)
        movieCreditsSingleWidth = singleTextWidth
        movieCreditsLaneWidth = (screenWidth - paddingPx * 2).toInt()
        
        val repeatedText = buildRepeatedMovieCreditsText(movieCreditsSingleText, singleTextWidth)
        val repeatedTextWidth = (measurePaint.measureText(repeatedText) + 1).toInt()
        
        // Measure single line height (without line spacing — setSingleLine ignores it)
        val singleLineH = measureSingleLineHeight(fontSize, lineHeight, isBold, isItalic, fontFamily)
        // Lane stride = line height * multiplier, so lineHeight controls gap between lanes
        val laneStride = (singleLineH * lineHeight).toInt()
        
        // Container with 3 lanes (clipped), centered vertically
        val totalLanesHeight = 2 * laneStride + singleLineH
        val topOffset = if (overlayHeightPx > 0) ((overlayHeightPx - totalLanesHeight) / 2).coerceAtLeast(0) else 0
        
        val container = android.widget.FrameLayout(this).apply {
            setBackgroundColor(finalBgColor)
            clipChildren = true
            clipToPadding = true
            if (mirror) scaleX = -1f
        }
        
        movieCreditsTextViews.clear()
        
        // Create 3 lanes: i=0 is top (line 1), i=2 is bottom (line 3)
        for (i in 0 until 3) {
            val lane = android.widget.FrameLayout(this).apply {
                clipChildren = true
                clipToPadding = true
                setPadding(paddingPx, 0, paddingPx, 0)
            }
            val laneParams = android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                singleLineH
            )
            laneParams.topMargin = topOffset + i * laneStride
            lane.layoutParams = laneParams
            
            // Single-line wide TextView inside each lane
            val tv = TextView(this).apply {
                this.text = repeatedText
                this.textSize = fontSize
                this.setTextColor(textColor)
                this.typeface = typeface
                this.setSingleLine(true)
                this.maxLines = 1
                this.setLineSpacing(0f, lineHeight)
                this.setShadowLayer(4f, 2f, 2f, shadowColor)
            }
            
            // Set explicit width so text is not truncated by parent
            val tvParams = android.widget.FrameLayout.LayoutParams(
                repeatedTextWidth,
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
            )
            lane.addView(tv, tvParams)
            movieCreditsTextViews.add(tv)
            container.addView(lane)
        }
        
        return container
    }
    
    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
    }
}
