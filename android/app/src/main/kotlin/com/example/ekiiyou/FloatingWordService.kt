package com.example.ekiiyou

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.File
import java.util.Locale
import kotlin.math.abs

class FloatingWordService : Service(), TextToSpeech.OnInitListener {

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var cardView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var cardParams: WindowManager.LayoutParams? = null

    private var badgeDotView: View? = null
    private var cardEnglishWordText: TextView? = null
    private var cardPhoneticText: TextView? = null
    private var cardArabicMeaningText: TextView? = null
    private var cardDefinitionText: TextView? = null
    private var cardProgressBadge: TextView? = null
    private var cardHeaderTitle: TextView? = null
    private var cardMarkReadBtn: TextView? = null
    private var cardNextWordBtn: TextView? = null

    private var mediaPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false

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
        tts = TextToSpeech(this, this)
        createNotificationChannel()
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.US
            ttsReady = true
        }
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
                    if (NativeBridgeStore.isArabic(this)) "✓ ممتاز! تم تسجيل قراءة الكلمة" else "✓ Word marked as read!",
                    Toast.LENGTH_SHORT
                ).show()
            }
            refreshCardContent()
            hideExpandedCard()
            updateForegroundNotification()
            return START_STICKY
        }

        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        ensureBubbleAdded()

        if (action == ACTION_SHOW_POPUP_NOW) {
            showExpandedCard()
        } else if (action == ACTION_REFRESH_CONTENT) {
            refreshCardContent()
            updateForegroundNotification()
        }

        schedulePeriodicPopup()
        return START_STICKY
    }

    private fun schedulePeriodicPopup() {
        handler.removeCallbacks(periodicPopupRunnable)
        val intervalMs = NativeBridgeStore.getFloatingIntervalMinutes(this) * 60_000L
        handler.postDelayed(periodicPopupRunnable, intervalMs)
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
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

        val container = FrameLayout(this)
        val bubbleSize = dp(58)

        val circleBg = GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(Color.parseColor("#1D4ED8"), Color.parseColor("#0F172A"))
        ).apply {
            shape = GradientDrawable.OVAL
            setStroke(dp(2), Color.parseColor("#60A5FA"))
        }

        val innerCircle = FrameLayout(this).apply {
            background = circleBg
            elevation = dp(8).toFloat()
        }

        val iconView = ImageView(this).apply {
            setImageResource(R.mipmap.launcher_icon)
            scaleType = ImageView.ScaleType.FIT_CENTER
            val pad = dp(10)
            setPadding(pad, pad, pad, pad)
        }
        innerCircle.addView(
            iconView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        container.addView(
            innerCircle,
            FrameLayout.LayoutParams(bubbleSize, bubbleSize).apply {
                gravity = Gravity.CENTER
            }
        )

        // Green/Blue unread badge dot on top-right of bubble
        val dot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#10B981"))
                setStroke(dp(2), Color.parseColor("#0F172A"))
            }
            elevation = dp(10).toFloat()
        }
        badgeDotView = dot
        container.addView(
            dot,
            FrameLayout.LayoutParams(dp(16), dp(16)).apply {
                gravity = Gravity.TOP or Gravity.END
                topMargin = dp(2)
                marginEnd = dp(2)
            }
        )

        val params = WindowManager.LayoutParams(
            dp(64),
            dp(64),
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - dp(72)
            y = resources.displayMetrics.heightPixels / 3
        }

        setupBubbleDragAndClick(container, params)

        try {
            windowManager?.addView(container, params)
            bubbleView = container
            bubbleParams = params
        } catch (_: Exception) {
        }
    }

    private fun setupBubbleDragAndClick(view: View, params: WindowManager.LayoutParams) {
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
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()
                    if (abs(dx) > dp(6) || abs(dy) > dp(6)) {
                        moved = true
                    }
                    params.x = initialX + dx
                    params.y = (initialY + dy).coerceIn(
                        dp(36),
                        resources.displayMetrics.heightPixels - dp(120)
                    )
                    try {
                        windowManager?.updateViewLayout(view, params)
                    } catch (_: Exception) {
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        toggleExpandedCard()
                    } else {
                        // Snap to nearest horizontal screen edge like Messenger chat head
                        val screenWidth = resources.displayMetrics.widthPixels
                        val mid = screenWidth / 2
                        params.x = if (params.x + view.width / 2 < mid) {
                            dp(8)
                        } else {
                            screenWidth - dp(72)
                        }
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
        if (cardView == null) {
            createCardView()
        }
        refreshCardContent()
        cardView?.visibility = View.VISIBLE
        badgeDotView?.visibility = View.GONE
    }

    private fun hideExpandedCard() {
        cardView?.visibility = View.GONE
    }

    private fun createCardView() {
        val isAr = NativeBridgeStore.isArabic(this)

        val rootCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = dp(16)
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.parseColor("#F70F172A"), Color.parseColor("#F71E293B"))
            ).apply {
                cornerRadius = dp(22).toFloat()
                setStroke(dp(1), Color.parseColor("#4D60A5FA"))
            }
            elevation = dp(16).toFloat()
        }

        // 1. Header Row (Logo + Title + Progress Badge + Collapse/Close)
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val logoImg = ImageView(this).apply {
            setImageResource(R.mipmap.launcher_icon)
        }
        headerRow.addView(logoImg, LinearLayout.LayoutParams(dp(22), dp(22)))

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

        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#CBD5E1"))
            textSize = 14f
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
                playCurrentWordAudio()
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
                        "✓ أحسنت! تم تسجيل قراءة الكلمة"
                    } else {
                        "✓ Great job! Word marked as read"
                    }
                    Toast.makeText(this@FloatingWordService, msg, Toast.LENGTH_SHORT).show()
                } else {
                    NativeBridgeStore.advanceToNextWord(this@FloatingWordService)
                }
                updateForegroundNotification()
                hideExpandedCard()
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

    private fun playCurrentWordAudio() {
        val wordObj = NativeBridgeStore.getCurrentWord(this) ?: return
        val wordText = wordObj.optString("word", "").trim()
        val localPath = wordObj.optString("audioLocalPath", "").trim()

        if (localPath.isNotBlank()) {
            val file = File(localPath)
            if (file.exists() && file.length() > 256) {
                try {
                    mediaPlayer?.release()
                    mediaPlayer = MediaPlayer().apply {
                        setDataSource(file.absolutePath)
                        prepare()
                        start()
                    }
                    return
                } catch (_: Exception) {
                }
            }
        }

        if (wordText.isNotBlank() && ttsReady) {
            tts?.speak(wordText, TextToSpeech.QUEUE_FLUSH, null, "floating_word_tts")
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
            cardView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {
        }
        bubbleView = null
        cardView = null
        mediaPlayer?.release()
        mediaPlayer = null
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

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
