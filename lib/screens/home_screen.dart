import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../models/prompter_settings.dart';
import '../widgets/text_preview.dart';
import '../widgets/color_picker_dialog.dart';
import '../services/native_overlay_service.dart';
import '../services/remote_server_service.dart';
import '../services/font_cache_service.dart';
import 'prompter_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  late TextEditingController _textController;
  bool _hasOverlayPermission = false;
  bool _isOverlayActive = false;
  StreamSubscription<String>? _remoteCommandSub;
  Timer? _overlayPollTimer;
  String _currentFontFilePath = '';
  String _currentFontKey = ''; // tracks which font was last downloaded
  Timer? _settingsDebounce;
  String? _overlayTextOverride; // when set, overlay uses this instead of app text

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _textController = TextEditingController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = Provider.of<PrompterSettings>(context, listen: false);
      _textController.text = settings.text;
      _checkOverlayPermission();
      // Listen for settings changes to push live updates to overlay
      settings.addListener(_onSettingsChanged);
      // Listen for remote commands (start_fullscreen, start_overlay)
      final remoteService = Provider.of<RemoteServerService>(context, listen: false);
      _remoteCommandSub = remoteService.commandStream.listen(_onRemoteCommand);
      // Pre-load Google Fonts so dropdown shows actual font styles
      _preloadGoogleFonts();
    });
  }

  void _preloadGoogleFonts() {
    const systemFonts = ['Arial', 'Times New Roman'];
    for (final font in PrompterSettings.availableFonts) {
      if (!systemFonts.contains(font)) {
        try {
          GoogleFonts.getFont(font);
        } catch (_) {}
      }
    }
    // Rebuild after fonts load
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() {});
    });
  }

  /// Push settings to overlay whenever they change in the app
  void _onSettingsChanged() {
    if (!_isOverlayActive) return;
    // Debounce: coalesce rapid changes into one update
    _settingsDebounce?.cancel();
    _settingsDebounce = Timer(const Duration(milliseconds: 50), () {
      _pushSettingsToOverlay();
    });
  }

  Future<void> _pushSettingsToOverlay() async {
    final settings = Provider.of<PrompterSettings>(context, listen: false);
    final fontKey = '${settings.fontFamily}_${settings.isBold}_${settings.isItalic}';

    // Send update immediately with whatever font path we have cached
    _sendOverlayUpdate(settings);

    // If font changed, download new font file in background, then push again
    if (fontKey != _currentFontKey) {
      _currentFontKey = fontKey;
      final fontPath = await FontCacheService.ensureFontFile(
        settings.fontFamily,
        isBold: settings.isBold,
        isItalic: settings.isItalic,
      );
      final newPath = fontPath ?? '';
      if (newPath != _currentFontFilePath) {
        _currentFontFilePath = newPath;
        // Push again with the correct font file
        if (_isOverlayActive && mounted) {
          final s = Provider.of<PrompterSettings>(context, listen: false);
          _sendOverlayUpdate(s);
        }
      }
    }
  }

  void _sendOverlayUpdate(PrompterSettings settings) {
    NativeOverlayService.updateSettings(
      text: _overlayTextOverride ?? settings.text,
      fontSize: settings.fontSize,
      textColor: settings.textColor.toARGB32(),
      backgroundColor: settings.backgroundColor.toARGB32(),
      speed: settings.scrollSpeed.toInt(),
      mirrorHorizontal: settings.mirrorHorizontal,
      fontFamily: settings.fontFamily,
      isBold: settings.isBold,
      isItalic: settings.isItalic,
      lineHeight: settings.lineHeight,
      textAlign: settings.textAlign.index,
      opacity: settings.opacity,
      paddingHorizontal: settings.paddingHorizontal,
      overlayPosition: settings.overlayPosition.index,
      overlayHeight: settings.overlayHeight,
      scrollMode: settings.scrollMode.index,
      fontFilePath: _currentFontFilePath,
    );
  }

  /// Handle commands received from remote control
  void _onRemoteCommand(String command) {
    if (!mounted) return;
    switch (command) {
      case 'start_fullscreen':
        _startPrompter(fromRemote: true);
        break;
      case 'start_overlay':
        _startOverlay(fromRemote: true);
        break;
      case 'apply_text':
        final remoteService = Provider.of<RemoteServerService>(context, listen: false);
        _overlayTextOverride = remoteService.remoteText;
        if (_isOverlayActive) {
          final s = Provider.of<PrompterSettings>(context, listen: false);
          _sendOverlayUpdate(s);
        }
        break;
      case 'play':
      case 'pause':
      case 'toggle':
        if (_isOverlayActive) {
          NativeOverlayService.togglePlayPause();
        }
        break;
      case 'reset':
        if (_isOverlayActive) {
          NativeOverlayService.resetScroll();
        }
        break;
      case 'forward':
        if (_isOverlayActive) {
          NativeOverlayService.scrollForward();
        }
        break;
    }
  }

  /// Sync overlay state back to app when resuming
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isOverlayActive) {
      _syncOverlayStateToApp();
    }
    if (state == AppLifecycleState.detached && _isOverlayActive) {
      NativeOverlayService.hideOverlay();
      _isOverlayActive = false;
      _stopOverlayPolling();
    }
  }

  Future<void> _syncOverlayStateToApp() async {
    try {
      final running = await NativeOverlayService.isOverlayRunning();
      if (!running) {
        setState(() => _isOverlayActive = false);
        _stopOverlayPolling();
        return;
      }
      final overlayState = await NativeOverlayService.getOverlayState();
      if (overlayState != null && mounted) {
        final settings = Provider.of<PrompterSettings>(context, listen: false);
        // Temporarily remove listener to avoid feedback loop
        settings.removeListener(_onSettingsChanged);
        
        final speed = overlayState['speed'] as int?;
        final color = overlayState['textColor'] as int?;
        final playing = overlayState['isPlaying'] as bool?;
        if (speed != null) settings.setScrollSpeed(speed.toDouble());
        if (color != null) settings.setTextColor(Color(color));
        if (playing != null && playing != settings.isPlaying) {
          settings.setPlaying(playing);
        }
        
        settings.addListener(_onSettingsChanged);
      }
    } catch (_) {}
  }

  Future<void> _checkOverlayPermission() async {
    if (_isAndroid) {
      // Check using native service
      final status = await NativeOverlayService.checkPermission();
      setState(() {
        _hasOverlayPermission = status;
      });
    }
  }

  void _startOverlayPolling() {
    _overlayPollTimer?.cancel();
    _overlayPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isOverlayActive && mounted) {
        _syncOverlayStateToApp();
      }
    });
  }

  void _stopOverlayPolling() {
    _overlayPollTimer?.cancel();
    _overlayPollTimer = null;
  }

  Future<void> _requestOverlayPermission() async {
    if (_isAndroid) {
      await NativeOverlayService.requestPermission();
      // Re-check after requesting
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkOverlayPermission();
    }
  }

  @override
  void dispose() {
    if (_isOverlayActive) {
      NativeOverlayService.hideOverlay();
    }
    _remoteCommandSub?.cancel();
    _overlayPollTimer?.cancel();
    _settingsDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final settings = Provider.of<PrompterSettings>(context, listen: false);
    settings.removeListener(_onSettingsChanged);
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _startPrompter({bool fromRemote = false}) {
    if (fromRemote) {
      // Use web remote text
      final remoteService = Provider.of<RemoteServerService>(context, listen: false);
      final settings = Provider.of<PrompterSettings>(context, listen: false);
      settings.setText(remoteService.remoteText);
    } else {
      // Use app's text
      final settings = Provider.of<PrompterSettings>(context, listen: false);
      settings.setText(_textController.text);
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PrompterScreen(),
      ),
    );
  }

  Future<void> _startOverlay({bool fromRemote = false}) async {
    if (!_hasOverlayPermission) {
      await _requestOverlayPermission();
      if (!_hasOverlayPermission) return;
    }

    final settings = Provider.of<PrompterSettings>(context, listen: false);

    if (fromRemote) {
      // Use web remote text for overlay
      final remoteService = Provider.of<RemoteServerService>(context, listen: false);
      _overlayTextOverride = remoteService.remoteText;
    } else {
      // Use app's text for overlay
      _overlayTextOverride = null;
      settings.setText(_textController.text);
    }
    
    // Download font file for native overlay
    final fontPath = await FontCacheService.ensureFontFile(
      settings.fontFamily,
      isBold: settings.isBold,
      isItalic: settings.isItalic,
    );
    _currentFontFilePath = fontPath ?? '';

    // Use native 2-layer overlay service with all settings
    await NativeOverlayService.showOverlay(
      text: _overlayTextOverride ?? settings.text,
      fontSize: settings.fontSize,
      textColor: settings.textColor.toARGB32(),
      backgroundColor: settings.backgroundColor.toARGB32(),
      speed: settings.scrollSpeed.toInt(),
      mirrorHorizontal: settings.mirrorHorizontal,
      fontFamily: settings.fontFamily,
      isBold: settings.isBold,
      isItalic: settings.isItalic,
      lineHeight: settings.lineHeight,
      textAlign: settings.textAlign.index,
      opacity: settings.opacity,
      paddingHorizontal: settings.paddingHorizontal,
      overlayPosition: settings.overlayPosition.index,
      overlayHeight: settings.overlayHeight,
      scrollMode: settings.scrollMode.index,
      fontFilePath: _currentFontFilePath,
    );
    
    setState(() => _isOverlayActive = true);
    // Native overlay auto-starts scrolling, sync isPlaying state
    settings.setPlaying(true);
    // Start polling native overlay state to sync play/pause back to web UI
    _startOverlayPolling();
    
    // Minimize app to show overlay (move to background, don't kill)
    if (mounted) {
      await const MethodChannel('com.ntt55.prompter/overlay')
          .invokeMethod('moveToBackground');
    }
  }

  Future<void> _requestAndStartOverlay() async {
    if (_isAndroid) {
      await NativeOverlayService.requestPermission();
      await Future.delayed(const Duration(milliseconds: 500));
      final hasPermission = await NativeOverlayService.checkPermission();
      if (hasPermission) {
        setState(() {
          _hasOverlayPermission = true;
        });
        // Automatically start overlay after permission granted
        await _startOverlay();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cần cấp quyền để sử dụng chế độ overlay'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _showStartOptions() {
    if (!_isAndroid) {
      _startPrompter();
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const Text('Toàn màn hình'),
              subtitle: const Text('Hiển thị prompter toàn màn hình'),
              onTap: () {
                Navigator.pop(context);
                _startPrompter();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.picture_in_picture,
                color: _hasOverlayPermission ? null : Colors.grey,
              ),
              title: const Text('Overlay (Đè trên app khác)'),
              subtitle: Text(
                _hasOverlayPermission
                    ? 'Hiển thị prompter đè trên các app khác'
                    : 'Cần cấp quyền trước khi sử dụng',
              ),
              trailing: !_hasOverlayPermission
                  ? TextButton(
                      onPressed: () async {
                        final status = await FlutterOverlayWindow.requestPermission();
                        if (status == true) {
                          setState(() {
                            _hasOverlayPermission = true;
                          });
                          // Refresh the bottom sheet
                          if (mounted) {
                            Navigator.pop(context);
                            _showStartOptions();
                          }
                        }
                      },
                      child: const Text('Cấp quyền'),
                    )
                  : null,
              onTap: _hasOverlayPermission
                  ? () async {
                      Navigator.pop(context);
                      await _startOverlay();
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompter'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.text_fields), text: 'Văn bản'),
            Tab(icon: Icon(Icons.format_paint), text: 'Định dạng'),
            Tab(icon: Icon(Icons.settings), text: 'Cài đặt'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Preview section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: TextPreview(),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTextTab(),
                _buildFormatTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showStartOptions,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Bắt đầu'),
      ),
    );
  }

  Widget _buildTextTab() {
    return Consumer<PrompterSettings>(
      builder: (context, settings, child) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _textController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'Nhập văn bản cần hiển thị...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: (value) {
              settings.setText(value);
            },
          ),
        );
      },
    );
  }

  Widget _buildFormatTab() {
    return Consumer<PrompterSettings>(
      builder: (context, settings, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Font family
              _buildSectionTitle('Font chữ'),
              DropdownButtonFormField<String>(
                value: settings.fontFamily,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: PrompterSettings.availableFonts.map((font) {
                  const systemFonts = ['Arial', 'Times New Roman'];
                  TextStyle fontStyle;
                  if (systemFonts.contains(font)) {
                    fontStyle = TextStyle(fontFamily: font, fontSize: 16);
                  } else {
                    try {
                      fontStyle = GoogleFonts.getFont(font, fontSize: 16);
                    } catch (e) {
                      fontStyle = const TextStyle(fontSize: 16);
                    }
                  }
                  return DropdownMenuItem(
                    value: font,
                    child: Text(font, style: fontStyle),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) settings.setFontFamily(value);
                },
              ),
              const SizedBox(height: 20),

              // Font size
              _buildSectionTitle('Cỡ chữ: ${settings.fontSize.toInt()}px'),
              Slider(
                value: settings.fontSize,
                min: 12,
                max: 120,
                divisions: 108,
                label: '${settings.fontSize.toInt()}px',
                onChanged: (value) => settings.setFontSize(value),
              ),
              const SizedBox(height: 20),

              // Bold & Italic
              _buildSectionTitle('Kiểu chữ'),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text('In đậm', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: settings.isBold,
                      onChanged: (_) => settings.toggleBold(),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text('In nghiêng', style: TextStyle(fontStyle: FontStyle.italic)),
                      value: settings.isItalic,
                      onChanged: (_) => settings.toggleItalic(),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Text color
              _buildSectionTitle('Màu chữ'),
              _buildColorButton(
                color: settings.textColor,
                onPressed: () async {
                  final color = await showDialog<Color>(
                    context: context,
                    builder: (context) => ColorPickerDialog(
                      initialColor: settings.textColor,
                      title: 'Chọn màu chữ',
                    ),
                  );
                  if (color != null) settings.setTextColor(color);
                },
              ),
              const SizedBox(height: 20),

              // Background color
              _buildSectionTitle('Màu nền'),
              _buildColorButton(
                color: settings.backgroundColor,
                onPressed: () async {
                  final color = await showDialog<Color>(
                    context: context,
                    builder: (context) => ColorPickerDialog(
                      initialColor: settings.backgroundColor,
                      title: 'Chọn màu nền',
                    ),
                  );
                  if (color != null) settings.setBackgroundColor(color);
                },
              ),
              const SizedBox(height: 20),

              // Text alignment
              _buildSectionTitle('Căn chỉnh'),
              SegmentedButton<TextAlign>(
                segments: const [
                  ButtonSegment(value: TextAlign.left, icon: Icon(Icons.format_align_left)),
                  ButtonSegment(value: TextAlign.center, icon: Icon(Icons.format_align_center)),
                  ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right)),
                  ButtonSegment(value: TextAlign.justify, icon: Icon(Icons.format_align_justify)),
                ],
                selected: {settings.textAlign},
                onSelectionChanged: (selection) {
                  settings.setTextAlign(selection.first);
                },
              ),
              const SizedBox(height: 20),

              // Line height
              _buildSectionTitle('Giãn dòng: ${settings.lineHeight.toStringAsFixed(1)}'),
              Slider(
                value: settings.lineHeight,
                min: 1.0,
                max: 3.0,
                divisions: 20,
                label: settings.lineHeight.toStringAsFixed(1),
                onChanged: (value) => settings.setLineHeight(value),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    return Consumer<PrompterSettings>(
      builder: (context, settings, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Scroll mode
              _buildSectionTitle('Kiểu cuộn chữ'),
              SegmentedButton<ScrollMode>(
                segments: const [
                  ButtonSegment(
                    value: ScrollMode.vertical,
                    label: Text('Dọc'),
                    icon: Icon(Icons.vertical_distribute),
                  ),
                  ButtonSegment(
                    value: ScrollMode.movieCredits,
                    label: Text('Movie Credits'),
                    icon: Icon(Icons.movie),
                  ),
                ],
                selected: {settings.scrollMode},
                onSelectionChanged: (Set<ScrollMode> selection) {
                  settings.setScrollMode(selection.first);
                },
              ),
              const SizedBox(height: 20),

              // Scroll speed
              _buildSectionTitle('Tốc độ cuộn: ${settings.scrollSpeed.toInt()} px/s'),
              Slider(
                value: settings.scrollSpeed,
                min: 10,
                max: 200,
                divisions: 190,
                label: '${settings.scrollSpeed.toInt()} px/s',
                onChanged: (value) => settings.setScrollSpeed(value),
              ),
              const SizedBox(height: 20),

              // Opacity
              _buildSectionTitle('Độ trong suốt: ${(settings.opacity * 100).toInt()}%'),
              Slider(
                value: settings.opacity,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                label: '${(settings.opacity * 100).toInt()}%',
                onChanged: (value) => settings.setOpacity(value),
              ),
              const SizedBox(height: 20),

              // Horizontal padding
              _buildSectionTitle('Lề ngang: ${settings.paddingHorizontal.toInt()}px'),
              Slider(
                value: settings.paddingHorizontal,
                min: 0,
                max: 100,
                divisions: 100,
                label: '${settings.paddingHorizontal.toInt()}px',
                onChanged: (value) => settings.setPaddingHorizontal(value),
              ),
              const SizedBox(height: 20),

              // Mirror
              SwitchListTile(
                title: const Text('Lật gương ngang'),
                subtitle: const Text('Hiển thị chữ ngược (dùng cho kính teleprompter)'),
                value: settings.mirrorHorizontal,
                onChanged: (_) => settings.toggleMirror(),
              ),
              const SizedBox(height: 20),

              // Overlay settings section
              const Divider(),
              _buildSectionTitle('Cài đặt Overlay'),
              const SizedBox(height: 8),
              
              // Overlay position
              const Text('Vị trí hiển thị:'),
              const SizedBox(height: 8),
              SegmentedButton<OverlayStripPosition>(
                segments: const [
                  ButtonSegment(
                    value: OverlayStripPosition.top,
                    label: Text('Trên'),
                    icon: Icon(Icons.vertical_align_top),
                  ),
                  ButtonSegment(
                    value: OverlayStripPosition.center,
                    label: Text('Giữa'),
                    icon: Icon(Icons.vertical_align_center),
                  ),
                  ButtonSegment(
                    value: OverlayStripPosition.bottom,
                    label: Text('Dưới'),
                    icon: Icon(Icons.vertical_align_bottom),
                  ),
                ],
                selected: {settings.overlayPosition},
                onSelectionChanged: (Set<OverlayStripPosition> selection) {
                  settings.setOverlayPosition(selection.first);
                },
              ),
              const SizedBox(height: 16),
              
              // Overlay height
              _buildSectionTitle('Chiều cao overlay: ${settings.overlayHeight.toInt()}px'),
              Slider(
                value: settings.overlayHeight,
                min: 80,
                max: 700,
                divisions: 62,
                label: '${settings.overlayHeight.toInt()}px',
                onChanged: (value) => settings.setOverlayHeight(value),
              ),
              const SizedBox(height: 20),

              // Remote control section
              const Divider(),
              _buildRemoteControlSection(),
              const SizedBox(height: 20),

              // Info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text('Hướng dẫn', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('• Toàn màn hình: Hiển thị prompter đầy màn hình'),
                      const Text('• Overlay: Hiển thị dải chữ trên camera khi quay phim'),
                      const Text('• Chạm 2 lần để tạm dừng/tiếp tục'),
                      const Text('• Kéo overlay để di chuyển vị trí'),
                      const Text('• Nhấn X trên notification để tắt overlay'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRemoteControlSection() {
    return Consumer<RemoteServerService>(
      builder: (context, server, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                _buildSectionTitle('Điều khiển từ xa'),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Bật Server'),
              subtitle: Text(
                server.isRunning
                    ? 'Đang chạy trên cổng ${server.port}'
                    : 'Cho phép điều khiển từ thiết bị khác qua Wi-Fi',
              ),
              value: server.isRunning,
              onChanged: (value) async {
                if (value) {
                  await server.startServer();
                } else {
                  await server.stopServer();
                }
              },
            ),
            if (server.isRunning) ...[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Primary connection URL
                      Row(
                        children: [
                          Icon(Icons.link, 
                            size: 18, 
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              server.connectionUrl,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'Sao chép IP',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: server.connectionUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã sao chép địa chỉ!'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Mở trình duyệt trên thiết bị cùng Wi-Fi và nhập địa chỉ trên',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${server.clientCount} thiết bị đang kết nối',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      // Show all available IPs if more than 1
                      if (server.allIps.length > 1) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Text(
                          'Nếu không kết nối được, thử các địa chỉ khác:',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...server.allIps.map((entry) {
                          final url = 'http://${entry.value}:${server.port}';
                          final isCurrent = entry.value == server.localIp;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Đã sao chép $url'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    isCurrent ? Icons.check_circle : Icons.circle_outlined,
                                    size: 14,
                                    color: isCurrent ? Colors.green : Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '$url  (${entry.key})',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.copy, size: 14, color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.4)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
              // Troubleshooting tips
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.help_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('Không kết nối được?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('• Đảm bảo 2 thiết bị cùng mạng Wi-Fi', style: TextStyle(fontSize: 12)),
                      const Text('• Nếu IP trên không đúng, thử các IP khác trong danh sách', style: TextStyle(fontSize: 12)),
                      const Text('• Tắt VPN trên cả 2 thiết bị nếu có', style: TextStyle(fontSize: 12)),
                      const Text('• Kiểm tra router không bật "AP Isolation"', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildColorButton({
    required Color color,
    required VoidCallback onPressed,
  }) {
    // Calculate luminance manually to avoid deprecated API
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Center(
          child: Icon(
            Icons.color_lens,
            color: luminance > 0.5 ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
