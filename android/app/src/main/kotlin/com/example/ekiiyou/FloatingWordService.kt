package com.example.ekiiyou

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlin.math.abs
import kotlin.math.hypot

class FloatingWordService : Service() {

    private var windowManager: WindowManager? = null
    private var bubbleView: BubbleCanvasView? = null
    private var dismissTargetView: DismissTargetCanvasView? = null
    private var cardView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var cardParams: WindowManager.LayoutParams? = null

    private var cardEnglishWordText: TextView? = null
    private var cardPhoneticText: TextView? = null
    private var cardArabicMeaningText: TextView? = null
    private var cardDefinitionText: TextView? = null
    private var cardProgressBadge: TextView? = null
    private var cardHeaderTitle: TextView? = null
    private var cardMarkReadBtn: TextView? = null
    private var cardNextWordBtn: TextView? = null

    private val handler = Handler(Looper.getMainLooper())
    private val periodicPopupRunnable = object : Runnable {
        override fun run() {
            if (!NativeBridgeStore.isFloatingEnabled(this@FloatingWordService)) {
                stopSelf()
                return
            }
            NativeBridgeStore.advanceToNextWord(this@FloatingWordService)
            if (Settings.canDrawOverlays(this@FloatingWordService)) {
                ensureBubbleAdded()
                bubbleView?.visibility = View.VISIBLE
                bubbleView?.showBadge = true
                showExpandedCard()
            }
            updateForegroundNotification()
            val intervalMs =
                NativeBridgeStore.getFloatingIntervalMinutes(this@FloatingWordService) * 60_000L
            handler.postDelayed(this, intervalMs)
        }
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == ACTION_STOP_SERVICE) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundSafely()

        if (action == ACTION_NOTIFICATION_MARK_READ) {
            val word = NativeBridgeStore.getCurrentWord(this)
            val wordId = word?.optInt("id", -1) ?: -1
            if (wordId > 0) {
                NativeBridgeStore.recordNativeReview(this, wordId, true)
                Toast.makeText(
                    this,
                    if (NativeBridgeStore.isArabic(this)) "✓ أحسنت! تم تسجيل قراءة الكلمة" else "✓ Word marked as read!",
                    Toast.LENGTH_SHORT
                ).show()
            }
            hideBubbleAndCardUntilNextSchedule()
            updateForegroundNotification()
            return START_STICKY
        }

        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_SHOW_POPUP_NOW) {
            ensureBubbleAdded()
            bubbleView?.visibility = View.VISIBLE
            showExpandedCard()
        } else if (action == ACTION_REFRESH_CONTENT) {
            if (cardView?.visibility == View.VISIBLE) {
                refreshCardContent()
            }
            updateForegroundNotification()
        } else if (bubbleView == null) {
            // Initial service start when enabled
            ensureBubbleAdded()
            bubbleView?.visibility = View.VISIBLE
        }

        schedulePeriodicPopup()
        return START_STICKY
    }

    private fun schedulePeriodicPopup() {
        handler.removeCallbacks(periodicPopupRunnable)
        val intervalMs = NativeBridgeStore.getFloatingIntervalMinutes(this) * 60_000L
        handler.postDelayed(periodicPopupRunnable, intervalMs)
    }

    /**
     * Hides both the floating bubble and the expanded word card completely,
     * and resets the timer so the next word pops up at the next scheduled interval.
     */
    private fun hideBubbleAndCardUntilNextSchedule() {
        hideExpandedCard()
        hideDismissTarget()
        bubbleView?.visibility = View.GONE
        schedulePeriodicPopup()
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private fun dpF(value: Float): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value,
            resources.displayMetrics
        )
    }

    private fun overlayType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun ensureBubbleAdded() {
        if (bubbleView != null) return

        val bubble = BubbleCanvasView(this)
        val size = dp(68)

        val params = WindowManager.LayoutParams(
            size,
            size,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - dp(74)
            y = resources.displayMetrics.heightPixels / 3
        }

        setupBubbleDragAndClick(bubble, params)

        try {
            windowManager?.addView(bubble, params)
            bubbleView = bubble
            bubbleParams = params
        } catch (_: Exception) {
        }
    }

    private fun ensureDismissTargetAdded() {
        if (dismissTargetView != null) return
        val target = DismissTargetCanvasView(this).apply {
            visibility = View.GONE
        }
        val size = dp(88)
        val params = WindowManager.LayoutParams(
            size,
            size,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(44)
        }
        try {
            windowManager?.addView(target, params)
            dismissTargetView = target
        } catch (_: Exception) {
        }
    }

    private fun showDismissTarget(hovered: Boolean) {
        ensureDismissTargetAdded()
        dismissTargetView?.let { target ->
            if (target.visibility != View.VISIBLE) {
                target.visibility = View.VISIBLE
            }
            if (target.isTargetActive != hovered) {
                target.isTargetActive = hovered
            }
        }
    }

    private fun hideDismissTarget() {
        dismissTargetView?.apply {
            isTargetActive = false
            visibility = View.GONE
        }
    }

    private fun isInsideDismissZone(rawX: Float, rawY: Float): Boolean {
        val metrics = resources.displayMetrics
        val targetCenterX = metrics.widthPixels / 2f
        val targetCenterY = metrics.heightPixels - dpF(88f)
        val dist = hypot((rawX - targetCenterX).toDouble(), (rawY - targetCenterY).toDouble())
        return dist <= dpF(95f) || rawY >= metrics.heightPixels - dpF(115f)
    }

    private fun setupBubbleDragAndClick(view: BubbleCanvasView, params: WindowManager.LayoutParams) {
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var moved = false

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moved = false
                    view.isPressedState = true
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()
                    if (abs(dx) > dp(6) || abs(dy) > dp(6)) {
                        moved = true
                        if (cardView?.visibility == View.VISIBLE) {
                            hideExpandedCard()
                        }
                        val overDismiss = isInsideDismissZone(event.rawX, event.rawY)
                        showDismissTarget(overDismiss)
                    }
                    params.x = initialX + dx
                    params.y = (initialY + dy).coerceIn(
                        dp(24),
                        resources.displayMetrics.heightPixels - dp(60)
                    )
                    try {
                        windowManager?.updateViewLayout(view, params)
                    } catch (_: Exception) {
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    view.isPressedState = false
                    val dismissed = moved && isInsideDismissZone(event.rawX, event.rawY)
                    hideDismissTarget()

                    if (dismissed) {
                        hideBubbleAndCardUntilNextSchedule()
                        val msg = if (NativeBridgeStore.isArabic(this@FloatingWordService)) {
                            "تم إخفاء الفقاعة — ستظهر تلقائياً في موعد الكلمة القادمة"
                        } else {
                            "Bubble hidden until the next scheduled word"
                        }
                        Toast.makeText(this@FloatingWordService, msg, Toast.LENGTH_SHORT).show()
                    } else if (!moved) {
                        toggleExpandedCard()
                    } else {
                        // Snap smoothly to nearest horizontal screen edge
                        val screenWidth = resources.displayMetrics.widthPixels
                        val mid = screenWidth / 2
                        params.x = if (params.x + view.width / 2 < mid) {
                            dp(4)
                        } else {
                            screenWidth - dp(72)
                        }
                        params.y = params.y.coerceIn(
                            dp(36),
                            resources.displayMetrics.heightPixels - dp(140)
                        )
                        try {
                            windowManager?.updateViewLayout(view, params)
                        } catch (_: Exception) {
                        }
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun toggleExpandedCard() {
        if (cardView?.visibility == View.VISIBLE) {
            hideExpandedCard()
        } else {
            showExpandedCard()
        }
    }

    private fun showExpandedCard() {
        if (!Settings.canDrawOverlays(this)) return
        ensureBubbleAdded()
        bubbleView?.visibility = View.VISIBLE
        if (cardView == null) {
            createCardView()
        }
        refreshCardContent()
        cardView?.visibility = View.VISIBLE
        bubbleView?.showBadge = false
    }

    private fun hideExpandedCard() {
        cardView?.visibility = View.GONE
    }

    private fun createCardView() {
        val isAr = NativeBridgeStore.isArabic(this)

        // Note: NO View.elevation on rootCard to prevent Android WindowManager
        // from rendering a semi-transparent rectangular box behind rounded corners.
        val rootCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = dp(16)
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.parseColor("#FA0F172A"), Color.parseColor("#FA1E293B"))
            ).apply {
                cornerRadius = dp(22).toFloat()
                setStroke(dp(1), Color.parseColor("#6660A5FA"))
            }
        }

        // 1. Header Row (Title + Progress Badge + Minimize + Close)
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val brandBadge = TextView(this).apply {
            text = "Aa"
            setTextColor(Color.WHITE)
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.parseColor("#2563EB"), Color.parseColor("#4C1D95"))
            ).apply {
                shape = GradientDrawable.OVAL
            }
        }
        headerRow.addView(brandBadge, LinearLayout.LayoutParams(dp(24), dp(24)))

        val headerTitle = TextView(this).apply {
            text = if (isAr) "EKiiYou • بطاقة كلمة ذكية" else "EKiiYou • Word Popup"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 11.5f
            setTypeface(typeface, Typeface.BOLD)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
            val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            lp.marginStart = dp(8)
            layoutParams = lp
        }
        cardHeaderTitle = headerTitle
        headerRow.addView(headerTitle)

        val progressBadge = TextView(this).apply {
            text = "0/10"
            setTextColor(Color.parseColor("#60A5FA"))
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(8), dp(3), dp(8), dp(3))
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.parseColor("#331E293B"))
                setStroke(dp(1), Color.parseColor("#4D60A5FA"))
            }
        }
        cardProgressBadge = progressBadge
        headerRow.addView(progressBadge)

        // Minimize to bubble button (—)
        val minimizeBtn = TextView(this).apply {
            text = "—"
            setTextColor(Color.parseColor("#CBD5E1"))
            textSize = 13f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
            val lp = LinearLayout.LayoutParams(dp(28), dp(28))
            lp.marginStart = dp(8)
            layoutParams = lp
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#33475569"))
            }
            setOnClickListener {
                hideExpandedCard()
            }
        }
        headerRow.addView(minimizeBtn)

        // Close until next schedule button (✕)
        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#FCA5A5"))
            textSize = 13f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
            val lp = LinearLayout.LayoutParams(dp(28), dp(28))
            lp.marginStart = dp(6)
            layoutParams = lp
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#33EF4444"))
            }
            setOnClickListener {
                hideBubbleAndCardUntilNextSchedule()
            }
        }
        headerRow.addView(closeBtn)
        rootCard.addView(headerRow)

        // 2. Word + Audio Speaker Row
        val wordRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dp(12)
            layoutParams = lp
        }

        val wordTextCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setOnClickListener {
                val w = NativeBridgeStore.getCurrentWord(this@FloatingWordService)
                val id = w?.optInt("id", -1)?.takeIf { it > 0 }
                hideExpandedCard()
                startActivity(
                    NativeBridgeStore.createAppLaunchIntent(
                        this@FloatingWordService,
                        NativeBridgeStore.ACTION_OPEN_WORD,
                        id
                    )
                )
            }
        }

        val englishWordTv = TextView(this).apply {
            text = "Serendipity"
            setTextColor(Color.WHITE)
            textSize = 21f
            setTypeface(typeface, Typeface.BOLD)
            textDirection = View.TEXT_DIRECTION_LTR
        }
        cardEnglishWordText = englishWordTv
        wordTextCol.addView(englishWordTv)

        val phoneticTv = TextView(this).apply {
            text = "/ˌser.ənˈdɪp.ə.ti/"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 12f
            textDirection = View.TEXT_DIRECTION_LTR
        }
        cardPhoneticText = phoneticTv
        wordTextCol.addView(phoneticTv)

        wordRow.addView(wordTextCol)

        val speakerBtn = TextView(this).apply {
            text = "🔊"
            textSize = 17f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(dp(42), dp(42)).apply {
                marginStart = dp(10)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#263B82F6"))
                setStroke(dp(1), Color.parseColor("#60A5FA"))
            }
            setOnClickListener {
                NativeBridgeStore.playCurrentWordAudio(this@FloatingWordService)
            }
        }
        wordRow.addView(speakerBtn)
        rootCard.addView(wordRow)

        // 3. Arabic Meaning Box
        val arabicMeaningTv = TextView(this).apply {
            text = "مصادفة سعيدة"
            setTextColor(Color.parseColor("#60A5FA"))
            textSize = 17f
            setTypeface(typeface, Typeface.BOLD)
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dp(8)
            layoutParams = lp
        }
        cardArabicMeaningText = arabicMeaningTv
        rootCard.addView(arabicMeaningTv)

        // 4. Definition / Example
        val definitionTv = TextView(this).apply {
            text = "Finding good things without looking for them"
            setTextColor(Color.parseColor("#CBD5E1"))
            textSize = 12.5f
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dp(4)
            layoutParams = lp
        }
        cardDefinitionText = definitionTv
        rootCard.addView(definitionTv)

        // 5. Action Buttons Row (✓ قرأتها  |  ↻ كلمة أخرى)
        val actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dp(14)
            layoutParams = lp
        }

        val markReadBtn = TextView(this).apply {
            text = if (isAr) "✓ قرأتها" else "✓ Read It"
            setTextColor(Color.WHITE)
            textSize = 13.5f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, dp(40), 1.3f)
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.parseColor("#10B981"), Color.parseColor("#059669"))
            ).apply {
                cornerRadius = dp(12).toFloat()
            }
            setOnClickListener {
                val word = NativeBridgeStore.getCurrentWord(this@FloatingWordService)
                val wordId = word?.optInt("id", -1) ?: -1
                if (wordId > 0) {
                    NativeBridgeStore.recordNativeReview(this@FloatingWordService, wordId, true)
                    val msg = if (NativeBridgeStore.isArabic(this@FloatingWordService)) {
                        "✓ أحسنت! تم تسجيل القراءة وستظهر الكلمة القادمة في موعدها"
                    } else {
                        "✓ Read recorded! Next word will appear on schedule"
                    }
                    Toast.makeText(this@FloatingWordService, msg, Toast.LENGTH_SHORT).show()
                } else {
                    NativeBridgeStore.advanceToNextWord(this@FloatingWordService)
                }
                updateForegroundNotification()
                // Hide both the card and the bubble until the next scheduled word time!
                hideBubbleAndCardUntilNextSchedule()
            }
        }
        cardMarkReadBtn = markReadBtn
        actionsRow.addView(markReadBtn)

        val nextWordBtn = TextView(this).apply {
            text = if (isAr) "↻ كلمة أخرى" else "↻ Next Word"
            setTextColor(Color.parseColor("#F8FAFC"))
            textSize = 13f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, dp(40), 1f).apply {
                marginStart = dp(8)
            }
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(Color.parseColor("#33475569"))
                setStroke(dp(1), Color.parseColor("#4D94A3B8"))
            }
            setOnClickListener {
                NativeBridgeStore.advanceToNextWord(this@FloatingWordService)
                refreshCardContent()
                updateForegroundNotification()
            }
        }
        cardNextWordBtn = nextWordBtn
        actionsRow.addView(nextWordBtn)

        rootCard.addView(actionsRow)

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - dp(32)).coerceAtMost(dp(360))

        val params = WindowManager.LayoutParams(
            cardWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(96)
        }

        // Allow dragging the expanded card vertically by its header row
        var cardInitialY = 0
        var cardInitialTouchY = 0f
        headerRow.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    cardInitialY = params.y
                    cardInitialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = (event.rawY - cardInitialTouchY).toInt()
                    params.y = (cardInitialY + dy).coerceIn(
                        dp(40),
                        resources.displayMetrics.heightPixels - dp(260)
                    )
                    try {
                        windowManager?.updateViewLayout(rootCard, params)
                    } catch (_: Exception) {
                    }
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(rootCard, params)
            cardView = rootCard
            cardParams = params
        } catch (_: Exception) {
        }
    }

    private fun refreshCardContent() {
        val isAr = NativeBridgeStore.isArabic(this)
        val reviewed = NativeBridgeStore.getReviewedToday(this)
        val target = NativeBridgeStore.getDailyTarget(this)
        val wordObj = NativeBridgeStore.getCurrentWord(this)

        cardHeaderTitle?.text =
            if (isAr) "EKiiYou • بطاقة كلمة ذكية" else "EKiiYou • Smart Word Popup"
        cardProgressBadge?.text = "$reviewed/$target"
        cardMarkReadBtn?.text = if (isAr) "✓ قرأتها" else "✓ Read It"
        cardNextWordBtn?.text = if (isAr) "↻ كلمة أخرى" else "↻ Next Word"

        if (wordObj != null) {
            val word = wordObj.optString("word", "")
            val phonetic = wordObj.optString("phonetic", "")
            val arabic = wordObj.optString("arabicMeaning", "")
            val definition = wordObj.optString("englishDefinition", "")
            val example = wordObj.optString("exampleSentence", "")

            cardEnglishWordText?.text = word
            if (phonetic.isNotBlank()) {
                cardPhoneticText?.text = phonetic
                cardPhoneticText?.visibility = View.VISIBLE
            } else {
                cardPhoneticText?.visibility = View.GONE
            }

            cardArabicMeaningText?.text = if (arabic.isNotBlank()) arabic else definition
            cardDefinitionText?.text = when {
                definition.isNotBlank() && example.isNotBlank() -> "$definition\n\"$example\""
                definition.isNotBlank() -> definition
                example.isNotBlank() -> "\"$example\""
                else -> if (isAr) "اضغط على الكلمة لفتح التفاصيل" else "Tap word to open full details"
            }
        } else {
            cardEnglishWordText?.text =
                if (isAr) "أضف كلماتك الأولى ✨" else "Add your first words ✨"
            cardPhoneticText?.visibility = View.GONE
            cardArabicMeaningText?.text =
                if (isAr) "افتح تطبيق EKiiYou لإضافة كلمات للمراجعة" else "Open EKiiYou to add vocabulary words"
            cardDefinitionText?.text = "EKiiYou Smart Vocabulary Notebook"
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "EKiiYou Floating Word Bubble",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Displays the floating vocabulary word bubble throughout the day"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val isAr = NativeBridgeStore.isArabic(this)
        val wordObj = NativeBridgeStore.getCurrentWord(this)
        val word = wordObj?.optString("word", "") ?: ""
        val arabic = wordObj?.optString("arabicMeaning", "") ?: ""

        val title = if (word.isNotBlank()) {
            if (arabic.isNotBlank()) "$word — $arabic" else word
        } else {
            if (isAr) "النافذة العائمة نشطة • EKiiYou" else "EKiiYou Floating Bubble Active"
        }

        val subtitle = if (isAr) {
            "اضغط لإظهار بطاقة الكلمة العائمة أو تعليمها كمقروءة"
        } else {
            "Tap to show the floating word popup or mark as read"
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        val showNowIntent = Intent(this, FloatingWordService::class.java).apply {
            action = ACTION_SHOW_POPUP_NOW
        }
        val showNowPending = PendingIntent.getService(this, 401, showNowIntent, flags)

        val markReadIntent = Intent(this, FloatingWordService::class.java).apply {
            action = ACTION_NOTIFICATION_MARK_READ
        }
        val markReadPending = PendingIntent.getService(this, 402, markReadIntent, flags)

        val stopIntent = Intent(this, FloatingWordService::class.java).apply {
            action = ACTION_STOP_SERVICE
        }
        val stopPending = PendingIntent.getService(this, 403, stopIntent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setContentIntent(showNowPending)
            .setOngoing(true)
            .addAction(
                android.R.drawable.checkbox_on_background,
                if (isAr) "✓ قرأتها" else "✓ Read",
                markReadPending
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                if (isAr) "إيقاف" else "Stop",
                stopPending
            )

        return builder.build()
    }

    private fun startForegroundSafely() {
        val notification = buildForegroundNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
        }
    }

    private fun updateForegroundNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildForegroundNotification())
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try {
            bubbleView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {
        }
        try {
            dismissTargetView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {
        }
        try {
            cardView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {
        }
        bubbleView = null
        dismissTargetView = null
        cardView = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Pure Canvas-rendered circular Messenger-style chat head bubble.
     * Draws a soft radial circular shadow, rich royal-blue/violet gradient sphere,
     * glass highlight, glowing ring, crisp vector "Aa" + open book emblem, and unread dot
     * with ZERO rectangular background or square WindowManager elevation artifacts.
     */
    private inner class BubbleCanvasView(context: Context) : View(context) {
        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val glassPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#22FFFFFF")
            style = Paint.Style.FILL
        }
        private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dpF(2.2f)
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textSize = dpF(17.5f)
        }
        private val bookPath = Path()
        private val bookPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#93C5FD")
            style = Paint.Style.STROKE
            strokeWidth = dpF(2.2f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val sparklePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FBBF24")
            style = Paint.Style.FILL
        }
        private val badgeFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#10B981")
            style = Paint.Style.FILL
        }
        private val badgeStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0F172A")
            style = Paint.Style.STROKE
            strokeWidth = dpF(2f)
        }

        var showBadge: Boolean = true
            set(value) {
                field = value
                invalidate()
            }

        var isPressedState: Boolean = false
            set(value) {
                field = value
                invalidate()
            }

        init {
            setBackgroundColor(Color.TRANSPARENT)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val scale = if (isPressedState) 0.93f else 1.0f
            val r = dpF(25f) * scale

            // 1. Soft 100% circular radial shadow (fades to transparent inside view bounds)
            val shadowRadius = r + dpF(7f)
            shadowPaint.shader = RadialGradient(
                cx,
                cy + dpF(2.5f),
                shadowRadius,
                intArrayOf(
                    Color.parseColor("#660F172A"),
                    Color.parseColor("#290F172A"),
                    Color.TRANSPARENT
                ),
                floatArrayOf(0f, 0.72f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(cx, cy + dpF(2.5f), shadowRadius, shadowPaint)

            // 2. Main sphere gradient (Royal Blue -> Deep Indigo/Violet)
            bodyPaint.shader = LinearGradient(
                cx - r,
                cy - r,
                cx + r,
                cy + r,
                intArrayOf(
                    Color.parseColor("#2563EB"),
                    Color.parseColor("#1D4ED8"),
                    Color.parseColor("#4C1D95")
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(cx, cy, r, bodyPaint)

            // 3. Top-left subtle glass reflection
            canvas.drawCircle(cx - r * 0.22f, cy - r * 0.28f, r * 0.58f, glassPaint)

            // 4. Crisp outer gradient ring
            ringPaint.shader = LinearGradient(
                cx - r,
                cy - r,
                cx + r,
                cy + r,
                Color.parseColor("#93C5FD"),
                Color.parseColor("#C4B5FD"),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(cx, cy, r - dpF(1.1f), ringPaint)

            // 5. Golden sparkle accent dot inside top-right
            canvas.drawCircle(cx + r * 0.42f, cy - r * 0.42f, dpF(2.3f), sparklePaint)

            // 6. Crisp "Aa" typography in the center
            val textY = cy + dpF(2f)
            canvas.drawText("Aa", cx, textY, textPaint)

            // 7. Open book curved pages motif beneath "Aa"
            val bookY = cy + dpF(9.5f)
            val wing = dpF(11f)
            bookPath.reset()
            bookPath.moveTo(cx - wing, bookY - dpF(1.5f))
            bookPath.quadTo(cx - wing * 0.45f, bookY + dpF(2.5f), cx, bookY + dpF(0.5f))
            bookPath.quadTo(cx + wing * 0.45f, bookY + dpF(2.5f), cx + wing, bookY - dpF(1.5f))
            canvas.drawPath(bookPath, bookPaint)

            // 8. Unread emerald badge dot on the top-right rim
            if (showBadge) {
                val bx = cx + r * 0.71f
                val by = cy - r * 0.71f
                val br = dpF(6f)
                canvas.drawCircle(bx, by, br, badgeFillPaint)
                canvas.drawCircle(bx, by, br, badgeStrokePaint)
            }
        }
    }

    /**
     * Messenger-style bottom "✕" drag-to-dismiss target circle.
     * Grows and turns vibrant red when the user drags the floating bubble over it.
     */
    private inner class DismissTargetCanvasView(context: Context) : View(context) {
        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dpF(2f)
        }
        private val crossPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = dpF(2.6f)
            strokeCap = Paint.Cap.ROUND
        }

        var isTargetActive: Boolean = false
            set(value) {
                field = value
                invalidate()
            }

        init {
            setBackgroundColor(Color.TRANSPARENT)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val r = if (isTargetActive) dpF(32f) else dpF(26f)

            val shadowRadius = r + dpF(8f)
            shadowPaint.shader = RadialGradient(
                cx,
                cy,
                shadowRadius,
                intArrayOf(
                    if (isTargetActive) Color.parseColor("#88EF4444") else Color.parseColor("#660F172A"),
                    Color.TRANSPARENT
                ),
                floatArrayOf(0.5f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(cx, cy, shadowRadius, shadowPaint)

            circlePaint.color =
                if (isTargetActive) Color.parseColor("#EEEF4444") else Color.parseColor("#D90F172A")
            canvas.drawCircle(cx, cy, r, circlePaint)

            borderPaint.color =
                if (isTargetActive) Color.WHITE else Color.parseColor("#99F87171")
            canvas.drawCircle(cx, cy, r - dpF(1f), borderPaint)

            val crossOffset = if (isTargetActive) dpF(8.5f) else dpF(7f)
            canvas.drawLine(
                cx - crossOffset,
                cy - crossOffset,
                cx + crossOffset,
                cy + crossOffset,
                crossPaint
            )
            canvas.drawLine(
                cx + crossOffset,
                cy - crossOffset,
                cx - crossOffset,
                cy + crossOffset,
                crossPaint
            )
        }
    }

    companion object {
        private const val CHANNEL_ID = "ekiiyou_floating_bubble_channel"
        private const val NOTIFICATION_ID = 9921

        const val ACTION_START_OR_UPDATE = "com.example.ekiiyou.FLOATING_START_OR_UPDATE"
        const val ACTION_SHOW_POPUP_NOW = "com.example.ekiiyou.FLOATING_SHOW_POPUP_NOW"
        const val ACTION_REFRESH_CONTENT = "com.example.ekiiyou.FLOATING_REFRESH_CONTENT"
        const val ACTION_NOTIFICATION_MARK_READ = "com.example.ekiiyou.FLOATING_NOTIF_MARK_READ"
        const val ACTION_STOP_SERVICE = "com.example.ekiiyou.FLOATING_STOP_SERVICE"

        fun syncServiceState(context: Context, showImmediately: Boolean = false) {
            val enabled = NativeBridgeStore.isFloatingEnabled(context)
            val canOverlay = Settings.canDrawOverlays(context)
            if ((enabled || showImmediately) && canOverlay) {
                val intent = Intent(context, FloatingWordService::class.java).apply {
                    action = if (showImmediately) ACTION_SHOW_POPUP_NOW else ACTION_START_OR_UPDATE
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (_: Exception) {
                }
            } else if (!enabled && !showImmediately) {
                try {
                    context.stopService(Intent(context, FloatingWordService::class.java))
                } catch (_: Exception) {
                }
            }
        }
    }
}
