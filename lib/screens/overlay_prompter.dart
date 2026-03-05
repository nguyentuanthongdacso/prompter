import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:ui' as ui;

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

  // Movie Credits mode state
  int _scrollMode = 0; // 0=vertical, 1=movieCredits
  double _movieCreditsOffset = 0.0;
  double _mcCycleHeight = 0.0;

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
      _scrollMode = data['scrollMode'] ?? _scrollMode;
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
    
    if (_scrollMode == 1) {
      // Movie Credits mode
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (_isPlaying) {
          setState(() {
            _movieCreditsOffset += _scrollSpeed / 60.0;
            if (_mcCycleHeight > 0 && _movieCreditsOffset >= _mcCycleHeight) {
              _movieCreditsOffset -= _mcCycleHeight;
            }
          });
        }
      });
    } else {
      // Regular vertical scroll
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
              // Scrolling text (mode-dependent)
              if (_scrollMode == 1)
                _buildMovieCreditsView(textStyle)
              else
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..scale(_mirrorHorizontal ? -1.0 : 1.0, 1.0, 1.0),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                      horizontal: _paddingHorizontal,
                      vertical: 80,
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

  Widget _buildMovieCreditsView(TextStyle textStyle) {
    // Convert multi-line text to single continuous line for horizontal scrolling
    final singleLineText = '${_text.replaceAll('\n', '     ')}     ';

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scale(_mirrorHorizontal ? -1.0 : 1.0, 1.0, 1.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lineWidth = constraints.maxWidth - _paddingHorizontal * 2;

          // Measure single line height
          final linePainter = TextPainter(
            text: TextSpan(text: 'Ág', style: textStyle),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          final lineHeight = linePainter.height;

          // Measure text width as single horizontal line
          final textPainter = TextPainter(
            text: TextSpan(text: singleLineText, style: textStyle),
            maxLines: 1,
            textDirection: ui.TextDirection.ltr,
          )..layout();
          final textWidth = textPainter.width;

          _mcCycleHeight = textWidth; // cycle = one full text width
          if (textWidth <= 0) return const SizedBox();

          final effectiveOffset = _movieCreditsOffset % textWidth;
          final copies = (3 * lineWidth / textWidth).ceil() + 2;
          final repeatedText = List.generate(copies, (_) => singleLineText).join();

          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _paddingHorizontal),
              child: SizedBox(
                height: lineHeight * 3,
                child: Column(
                  children: [
                    // Line 1 (top) — oldest text, exits here
                    _buildCreditsLine(repeatedText, textStyle, lineWidth,
                        effectiveOffset, lineHeight),
                    // Line 2 (middle)
                    _buildCreditsLine(repeatedText, textStyle, lineWidth,
                        effectiveOffset + lineWidth, lineHeight),
                    // Line 3 (bottom) — newest text, enters here
                    _buildCreditsLine(repeatedText, textStyle, lineWidth,
                        effectiveOffset + 2 * lineWidth, lineHeight),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCreditsLine(String repeatedText, TextStyle style, double lineWidth,
      double offset, double lineHeight) {
    return SizedBox(
      height: lineHeight,
      width: lineWidth,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: Offset(-offset, 0),
            child: Text(repeatedText, style: style, maxLines: 1, softWrap: false),
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
