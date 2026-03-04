package com.ntt55.prompter

import android.content.Intent
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
                    val textColor = (call.argument<Long>("textColor") ?: 0xFF000000L).toInt()
                    val speed = (call.argument<Number>("speed")?.toInt()) ?: 50
                    val mirrorHorizontal = call.argument<Boolean>("mirrorHorizontal") ?: false
                    
                    val intent = Intent(this, PrompterOverlayService::class.java).apply {
                        action = PrompterOverlayService.ACTION_SHOW
                        putExtra(PrompterOverlayService.EXTRA_TEXT, text)
                        putExtra(PrompterOverlayService.EXTRA_FONT_SIZE, fontSize)
                        putExtra(PrompterOverlayService.EXTRA_TEXT_COLOR, textColor)
                        putExtra(PrompterOverlayService.EXTRA_SPEED, speed)
                        putExtra(PrompterOverlayService.EXTRA_MIRROR, mirrorHorizontal)
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
                
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                
                else -> result.notImplemented()
            }
        }
    }
}
