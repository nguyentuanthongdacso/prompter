import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';

class OverlayPrompter extends StatefulWidget {
  const OverlayPrompter({super.key});

  @override
  State<OverlayPrompter> createState() => _OverlayPrompterState();
}

class _OverlayPrompterState extends State<OverlayPrompter> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollTimer;
  bool _isPlaying = false;  // Start paused until settings received
  bool _showControls = true;
  bool _settingsReceived = false;
  
  // Default settings - black text on transparent background
  String _text = 'Đang chờ dữ liệu từ app chính...';
  double _scrollSpeed = 50.0;
  String _fontFamily = 'Roboto';
  double _fontSize = 32.0;
  bool _isBold = true;
  bool _isItalic = false;
  Color _textColor = Colors.black;
  Color _backgroundColor = Colors.transparent;
  double _opacity = 0.0; // Fully transparent background
  bool _mirrorHorizontal = false;
  double _lineHeight = 1.5;
  TextAlign _textAlign = TextAlign.center;
  double _paddingHorizontal = 24.0;

  @override
  void initState() {
    super.initState();
    
    // Listen for data from main app
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map<String, dynamic>) {
        _updateSettings(event);
        // Start scrolling after receiving settings
        setState(() => _settingsReceived = true);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_isPlaying) {
            _startScrolling();
          }
        });
      }
    });

    // Auto-hide controls after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _updateSettings(Map<String, dynamic> data) {
    setState(() {
      _text = data['text'] ?? _text;
      _scrollSpeed = (data['scrollSpeed'] ?? _scrollSpeed).toDouble();
      _fontFamily = data['fontFamily'] ?? _fontFamily;
      _fontSize = (data['fontSize'] ?? _fontSize).toDouble();
      _isBold = data['isBold'] ?? _isBold;
      _isItalic = data['isItalic'] ?? _isItalic;
      final textColorValue = data['textColor'] ?? _textColor.value;
      _textColor = Color.fromARGB(
        (textColorValue >> 24) & 0xFF,
        (textColorValue >> 16) & 0xFF,
        (textColorValue >> 8) & 0xFF,
        textColorValue & 0xFF,
      );
      final bgColorValue = data['backgroundColor'] ?? _backgroundColor.value;
      _backgroundColor = Color.fromARGB(
        (bgColorValue >> 24) & 0xFF,
        (bgColorValue >> 16) & 0xFF,
        (bgColorValue >> 8) & 0xFF,
        bgColorValue & 0xFF,
      );
      _opacity = (data['opacity'] ?? _opacity).toDouble();
      _mirrorHorizontal = data['mirrorHorizontal'] ?? _mirrorHorizontal;
      _lineHeight = (data['lineHeight'] ?? _lineHeight).toDouble();
      _paddingHorizontal = (data['paddingHorizontal'] ?? _paddingHorizontal).toDouble();
      
      final alignIndex = data['textAlign'] ?? 1;
      _textAlign = TextAlign.values[alignIndex];
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startScrolling() {
    _scrollTimer?.cancel();
    setState(() => _isPlaying = true);
    
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_scrollController.hasClients && _isPlaying) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.offset;
        
        if (currentScroll >= maxScroll) {
          _pauseScrolling();
          return;
        }
        
        final pixelsPerFrame = _scrollSpeed / 60.0;
        _scrollController.jumpTo(currentScroll + pixelsPerFrame);
      }
    });
  }

  void _pauseScrolling() {
    _scrollTimer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _pauseScrolling();
    } else {
      _startScrolling();
    }
  }

  void _closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  TextStyle _getTextStyle() {
    try {
      return GoogleFonts.getFont(
        _fontFamily,
        fontSize: _fontSize,
        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
        color: _textColor,
        height: _lineHeight,
      );
    } catch (e) {
      return TextStyle(
        fontSize: _fontSize,
        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
        color: _textColor,
        height: _lineHeight,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = _getTextStyle();

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: _togglePlayPause,
        child: Container(
          color: Color.fromRGBO(
            _backgroundColor.red,
            _backgroundColor.green,
            _backgroundColor.blue,
            _opacity,
          ),
          child: Stack(
            children: [
              // Scrolling text
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(_mirrorHorizontal ? -1.0 : 1.0, 1.0, 1.0),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: _paddingHorizontal,
                    vertical: 80, // Space for control panel
                  ),
                  child: Text(
                    _text,
                    style: textStyle,
                    textAlign: _textAlign,
                  ),
                ),
              ),

              // Floating Control Panel - bottom right
              Positioned(
                bottom: 100,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Scroll up
                      _controlButton(
                        Icons.keyboard_arrow_up,
                        () => _scrollController.animateTo(
                          (_scrollController.offset - 100).clamp(0, _scrollController.position.maxScrollExtent),
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Play/Pause
                      _controlButton(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        _togglePlayPause,
                        size: 32,
                        highlight: true,
                      ),
                      const SizedBox(height: 4),
                      // Scroll down
                      _controlButton(
                        Icons.keyboard_arrow_down,
                        () => _scrollController.animateTo(
                          (_scrollController.offset + 100).clamp(0, _scrollController.position.maxScrollExtent),
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Close button
                      _controlButton(
                        Icons.close,
                        _closeOverlay,
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onTap, {Color? color, double size = 24, bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(highlight ? 12 : 8),
        decoration: BoxDecoration(
          color: color ?? (highlight ? Colors.white.withValues(alpha: 0.2) : Colors.transparent),
          shape: BoxShape.circle,
          border: highlight ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}
