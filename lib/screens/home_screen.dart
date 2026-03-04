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
import 'prompter_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _textController;
  bool _hasOverlayPermission = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _textController = TextEditingController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = Provider.of<PrompterSettings>(context, listen: false);
      _textController.text = settings.text;
      _checkOverlayPermission();
    });
  }

  Future<void> _checkOverlayPermission() async {
    if (_isAndroid) {
      final status = await FlutterOverlayWindow.isPermissionGranted();
      setState(() {
        _hasOverlayPermission = status;
      });
    }
  }

  Future<void> _requestOverlayPermission() async {
    if (_isAndroid) {
      final status = await FlutterOverlayWindow.requestPermission();
      setState(() {
        _hasOverlayPermission = status ?? false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _startPrompter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PrompterScreen(),
      ),
    );
  }

  Future<void> _startOverlay() async {
    if (!_hasOverlayPermission) {
      await _requestOverlayPermission();
      if (!_hasOverlayPermission) return;
    }

    final settings = Provider.of<PrompterSettings>(context, listen: false);
    
    // Start the overlay - FULLSCREEN with transparent background
    await FlutterOverlayWindow.showOverlay(
      enableDrag: false,
      height: WindowSize.fullCover,
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.center,
      positionGravity: PositionGravity.none,
      overlayTitle: "Prompter",
      overlayContent: "Đang chạy chữ...",
      flag: OverlayFlag.clickThrough, // Allow clicks to pass through
      visibility: NotificationVisibility.visibilityPublic,
    );

    // Small delay to ensure overlay is ready
    await Future.delayed(const Duration(milliseconds: 500));

    // Send settings to overlay
    await FlutterOverlayWindow.shareData({
      'text': settings.text,
      'scrollSpeed': settings.scrollSpeed,
      'fontFamily': settings.fontFamily,
      'fontSize': settings.fontSize,
      'isBold': settings.isBold,
      'isItalic': settings.isItalic,
      'textColor': settings.textColor.value,
      'backgroundColor': settings.backgroundColor.value,
      'opacity': settings.opacity,
      'mirrorHorizontal': settings.mirrorHorizontal,
      'lineHeight': settings.lineHeight,
      'textAlign': settings.textAlign.index,
      'paddingHorizontal': settings.paddingHorizontal,
    });
  }

  Future<void> _requestAndStartOverlay() async {
    if (_isAndroid) {
      final status = await FlutterOverlayWindow.requestPermission();
      if (status == true) {
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
                      // Minimize app to background after starting overlay
                      if (mounted) {
                        await SystemChannels.platform.invokeMethod('SystemNavigator.pop');
                      }
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
                  TextStyle? fontStyle;
                  try {
                    fontStyle = GoogleFonts.getFont(font);
                  } catch (e) {
                    fontStyle = null;
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
                min: 0.1,
                max: 1.0,
                divisions: 9,
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
                max: 400,
                divisions: 32,
                label: '${settings.overlayHeight.toInt()}px',
                onChanged: (value) => settings.setOverlayHeight(value),
              ),
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
