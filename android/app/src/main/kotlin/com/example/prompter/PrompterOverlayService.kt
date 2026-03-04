package com.example.prompter

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
    private var scrollSpeed = 50
    private var scrollHandler: Handler? = null
    private var scrollRunnable: Runnable? = null
    private var currentTextColor = Color.BLACK
    
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
        const val ACTION_PLAY_PAUSE = "com.example.prompter.PLAY_PAUSE"
        const val ACTION_SPEED_UP = "com.example.prompter.SPEED_UP"
        const val ACTION_SPEED_DOWN = "com.example.prompter.SPEED_DOWN"
        const val ACTION_SCROLL_UP = "com.example.prompter.SCROLL_UP"
        const val ACTION_SCROLL_DOWN = "com.example.prompter.SCROLL_DOWN"
        
        const val EXTRA_TEXT = "text"
        const val EXTRA_FONT_SIZE = "fontSize"
        const val EXTRA_TEXT_COLOR = "textColor"
        const val EXTRA_SPEED = "speed"
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        scrollHandler = Handler(Looper.getMainLooper())
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val text = intent.getStringExtra(EXTRA_TEXT) ?: "No text"
                val fontSize = intent.getFloatExtra(EXTRA_FONT_SIZE, 24f)
                val textColor = intent.getIntExtra(EXTRA_TEXT_COLOR, Color.BLACK)
                scrollSpeed = intent.getIntExtra(EXTRA_SPEED, 50)
                showOverlay(text, fontSize, textColor)
                startForeground(NOTIFICATION_ID, createNotification())
            }
            ACTION_HIDE -> {
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
        }
        return START_STICKY
    }
    
    private fun showOverlay(text: String, fontSize: Float, textColor: Int) {
        if (textOverlayView != null) return
        
        // === Layer 1: Text Overlay (Click-through) ===
        textOverlayView = createTextOverlayView(text, fontSize, textColor)
        
        val textParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) 
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 
            else 
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or  // Click-through!
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        textParams.gravity = Gravity.TOP or Gravity.START
        
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
    
    private fun createTextOverlayView(text: String, fontSize: Float, textColor: Int): View {
        val scrollView = ScrollView(this).apply {
            id = View.generateViewId()
            setBackgroundColor(Color.TRANSPARENT)
            isVerticalScrollBarEnabled = false
        }
        
        val textView = TextView(this).apply {
            this.text = text
            this.textSize = fontSize
            this.setTextColor(textColor)
            this.setPadding(48, 200, 48, 200)
            this.gravity = Gravity.CENTER_HORIZONTAL
            this.setLineSpacing(8f, 1.2f)
            // Add text shadow for better visibility
            this.setShadowLayer(4f, 2f, 2f, Color.WHITE)
        }
        
        scrollView.addView(textView)
        scrollView.tag = textView // Store reference to TextView
        
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
        (textOverlayView as? ScrollView)?.let { scrollView ->
            (scrollView.tag as? TextView)?.text = text
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
        scrollRunnable = object : Runnable {
            override fun run() {
                if (isPlaying) {
                    (textOverlayView as? ScrollView)?.let { scrollView ->
                        val currentY = scrollView.scrollY
                        val maxY = scrollView.getChildAt(0)?.height?.minus(scrollView.height) ?: 0
                        
                        if (currentY < maxY) {
                            // Scroll step based on speed: higher speed = more pixels per step
                            val scrollStep = (scrollSpeed / 20).coerceIn(1, 15)
                            scrollView.scrollBy(0, scrollStep)
                        } else {
                            // Reached end, stop
                            isPlaying = false
                            controlPanelView?.findViewWithTag<TextView>("playPauseBtn")?.text = "▶"
                            return
                        }
                    }
                    // Fixed 33ms delay (~30fps) for smooth animation
                    scrollHandler?.postDelayed(this, 33L)
                }
            }
        }
        scrollHandler?.post(scrollRunnable!!)
    }
    
    private fun stopScrolling() {
        scrollRunnable?.let { scrollHandler?.removeCallbacks(it) }
    }
    
    private fun speedUp() {
        scrollSpeed = (scrollSpeed + 20).coerceAtMost(300)
    }
    
    private fun speedDown() {
        scrollSpeed = (scrollSpeed - 20).coerceAtLeast(20)
    }
    
    private fun scrollUp() {
        (textOverlayView as? ScrollView)?.smoothScrollBy(0, -200)
    }
    
    private fun scrollDown() {
        (textOverlayView as? ScrollView)?.smoothScrollBy(0, 200)
    }
    
    private fun changeTextColor(color: Int) {
        currentTextColor = color
        (textOverlayView as? ScrollView)?.let { scrollView ->
            (scrollView.tag as? TextView)?.setTextColor(color)
            // Update shadow color for better contrast
            val shadowColor = if (color == Color.WHITE || color == Color.YELLOW) Color.BLACK else Color.WHITE
            (scrollView.tag as? TextView)?.setShadowLayer(4f, 2f, 2f, shadowColor)
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
    
    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
    }
}
