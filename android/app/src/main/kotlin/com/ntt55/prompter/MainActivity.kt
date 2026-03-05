package com.ntt55.prompter

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private val CHANNEL = "com.ntt55.prompter/overlay"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(hasPermission)
                }
                
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivityForResult(intent, 1234)
                    }
                    result.success(true)
                }
                
                "showOverlay" -> {
                    val text = call.argument<String>("text") ?: "No text"
                    val fontSize = call.argument<Double>("fontSize")?.toFloat() ?: 24f
                    val textColor = (call.argument<Number>("textColor")?.toInt()) ?: Color.BLACK
                    val bgColor = (call.argument<Number>("backgroundColor")?.toInt()) ?: Color.TRANSPARENT
                    val speed = (call.argument<Number>("speed")?.toInt()) ?: 50
                    val mirrorHorizontal = call.argument<Boolean>("mirrorHorizontal") ?: false
                    val fontFamily = call.argument<String>("fontFamily") ?: "Roboto"
                    val isBold = call.argument<Boolean>("isBold") ?: false
                    val isItalic = call.argument<Boolean>("isItalic") ?: false
                    val lineHeight = call.argument<Double>("lineHeight")?.toFloat() ?: 1.5f
                    val textAlign = (call.argument<Number>("textAlign")?.toInt()) ?: 1
                    val opacity = call.argument<Double>("opacity")?.toFloat() ?: 0f
                    val paddingH = call.argument<Double>("paddingHorizontal")?.toFloat() ?: 20f
                    val overlayPos = (call.argument<Number>("overlayPosition")?.toInt()) ?: 2
                    val overlayHeight = call.argument<Double>("overlayHeight")?.toFloat() ?: 150f
                    val scrollMode = (call.argument<Number>("scrollMode")?.toInt()) ?: 0
                    
                    val intent = Intent(this, PrompterOverlayService::class.java).apply {
                        action = PrompterOverlayService.ACTION_SHOW
                        putExtra(PrompterOverlayService.EXTRA_TEXT, text)
                        putExtra(PrompterOverlayService.EXTRA_FONT_SIZE, fontSize)
                        putExtra(PrompterOverlayService.EXTRA_TEXT_COLOR, textColor)
                        putExtra(PrompterOverlayService.EXTRA_BG_COLOR, bgColor)
                        putExtra(PrompterOverlayService.EXTRA_SPEED, speed)
                        putExtra(PrompterOverlayService.EXTRA_MIRROR, mirrorHorizontal)
                        putExtra(PrompterOverlayService.EXTRA_FONT_FAMILY, fontFamily)
                        putExtra(PrompterOverlayService.EXTRA_IS_BOLD, isBold)
                        putExtra(PrompterOverlayService.EXTRA_IS_ITALIC, isItalic)
                        putExtra(PrompterOverlayService.EXTRA_LINE_HEIGHT, lineHeight)
                        putExtra(PrompterOverlayService.EXTRA_TEXT_ALIGN, textAlign)
                        putExtra(PrompterOverlayService.EXTRA_OPACITY, opacity)
                        putExtra(PrompterOverlayService.EXTRA_PADDING_H, paddingH)
                        putExtra(PrompterOverlayService.EXTRA_OVERLAY_POS, overlayPos)
                        putExtra(PrompterOverlayService.EXTRA_OVERLAY_HEIGHT, overlayHeight)
                        putExtra(PrompterOverlayService.EXTRA_SCROLL_MODE, scrollMode)
                    }
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    
                    result.success(true)
                }
                
                "hideOverlay" -> {
                    val intent = Intent(this, PrompterOverlayService::class.java).apply {
                        action = PrompterOverlayService.ACTION_HIDE
                    }
                    startService(intent)
                    result.success(true)
                }
                
                "updateText" -> {
                    val text = call.argument<String>("text") ?: return@setMethodCallHandler
                    val intent = Intent(this, PrompterOverlayService::class.java).apply {
                        action = PrompterOverlayService.ACTION_UPDATE_TEXT
                        putExtra(PrompterOverlayService.EXTRA_TEXT, text)
                    }
                    startService(intent)
                    result.success(true)
                }
                
                "updateSettings" -> {
                    val text = call.argument<String>("text") ?: "No text"
                    val fontSize = call.argument<Double>("fontSize")?.toFloat() ?: 24f
                    val textColor = (call.argument<Number>("textColor")?.toInt()) ?: Color.BLACK
                    val bgColor = (call.argument<Number>("backgroundColor")?.toInt()) ?: Color.TRANSPARENT
                    val speed = (call.argument<Number>("speed")?.toInt()) ?: 50
                    val mirrorHorizontal = call.argument<Boolean>("mirrorHorizontal") ?: false
                    val fontFamily = call.argument<String>("fontFamily") ?: "Roboto"
                    val isBold = call.argument<Boolean>("isBold") ?: false
                    val isItalic = call.argument<Boolean>("isItalic") ?: false
                    val lineHeight = call.argument<Double>("lineHeight")?.toFloat() ?: 1.5f
                    val textAlign = (call.argument<Number>("textAlign")?.toInt()) ?: 1
                    val opacity = call.argument<Double>("opacity")?.toFloat() ?: 0f
                    val paddingH = call.argument<Double>("paddingHorizontal")?.toFloat() ?: 20f
                    val overlayPos = (call.argument<Number>("overlayPosition")?.toInt()) ?: 2
                    val overlayHeight = call.argument<Double>("overlayHeight")?.toFloat() ?: 150f
                    val scrollMode = (call.argument<Number>("scrollMode")?.toInt()) ?: 0
                    
                    val intent = Intent(this, PrompterOverlayService::class.java).apply {
                        action = PrompterOverlayService.ACTION_UPDATE_SETTINGS
                        putExtra(PrompterOverlayService.EXTRA_TEXT, text)
                        putExtra(PrompterOverlayService.EXTRA_FONT_SIZE, fontSize)
                        putExtra(PrompterOverlayService.EXTRA_TEXT_COLOR, textColor)
                        putExtra(PrompterOverlayService.EXTRA_BG_COLOR, bgColor)
                        putExtra(PrompterOverlayService.EXTRA_SPEED, speed)
                        putExtra(PrompterOverlayService.EXTRA_MIRROR, mirrorHorizontal)
                        putExtra(PrompterOverlayService.EXTRA_FONT_FAMILY, fontFamily)
                        putExtra(PrompterOverlayService.EXTRA_IS_BOLD, isBold)
                        putExtra(PrompterOverlayService.EXTRA_IS_ITALIC, isItalic)
                        putExtra(PrompterOverlayService.EXTRA_LINE_HEIGHT, lineHeight)
                        putExtra(PrompterOverlayService.EXTRA_TEXT_ALIGN, textAlign)
                        putExtra(PrompterOverlayService.EXTRA_OPACITY, opacity)
                        putExtra(PrompterOverlayService.EXTRA_PADDING_H, paddingH)
                        putExtra(PrompterOverlayService.EXTRA_OVERLAY_POS, overlayPos)
                        putExtra(PrompterOverlayService.EXTRA_OVERLAY_HEIGHT, overlayHeight)
                        putExtra(PrompterOverlayService.EXTRA_SCROLL_MODE, scrollMode)
                    }
                    startService(intent)
                    result.success(true)
                }
                
                "isOverlayRunning" -> {
                    result.success(PrompterOverlayService.isRunning)
                }
                
                "getOverlayState" -> {
                    val state = mapOf(
                        "speed" to PrompterOverlayService.currentSpeed,
                        "textColor" to PrompterOverlayService.currentColor
                    )
                    result.success(state)
                }
                
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                
                else -> result.notImplemented()
            }
        }
    }
}
