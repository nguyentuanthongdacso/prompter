import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../models/prompter_settings.dart';
import '../services/remote_server_service.dart';

class PrompterScreen extends StatefulWidget {
  final double initialProgress;
  const PrompterScreen({super.key, this.initialProgress = 0.0});

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen> with WindowListener {
  late ScrollController _scrollController;
  Timer? _scrollTimer;
  bool _isPlaying = false;
  bool _showControls = true;
  double _currentSpeed = 50.0;
  bool _isAlwaysOnTop = false;

  // Movie Credits mode state
  double _movieCreditsOffset = 0.0;
  double _mcCycleHeight = 0.0;

  // Listener for remote control sync
  late PrompterSettings _settings;
  bool _suppressSettingsSync = false;
  StreamSubscription<String>? _remoteCommandSub;

  // Scroll progress broadcasting for web live preview
  Timer? _scrollProgressTimer;

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    // Hide status bar for immersive experience on mobile
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    
    // Set up window for desktop
    if (_isDesktop) {
      windowManager.addListener(this);
      _setupDesktopWindow();
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settings = Provider.of<PrompterSettings>(context, listen: false);
      _currentSpeed = _settings.scrollSpeed;
      _settings.addListener(_onRemoteSettingsChanged);
      // Listen for remote seek commands
      final remoteService = Provider.of<RemoteServerService>(context, listen: false);
      _remoteCommandSub = remoteService.commandStream.listen(_onRemoteCommand);
      remoteService.broadcastDisplayState(mode: 'fullscreen', isActive: true);
      _startScrollProgressBroadcast();
      // Resume from initial progress if provided
      if (widget.initialProgress > 0.0) {
        _applyInitialProgress(widget.initialProgress);
      }
      _startScrolling();
    });
    
    // Auto-hide controls after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// React to settings changes triggered from remote control
  void _onRemoteSettingsChanged() {
    if (!mounted || _suppressSettingsSync) return;
    // Sync play/pause state
    if (_settings.isPlaying && !_isPlaying) {
      _startScrolling();
    } else if (!_settings.isPlaying && _isPlaying) {
      _pauseScrolling();
    }
    // Sync speed
    if (_settings.scrollSpeed != _currentSpeed) {
      setState(() {
        _currentSpeed = _settings.scrollSpeed;
      });
    }
  }

  /// Handle seek commands from remote control
  void _onRemoteCommand(String command) {
    if (!mounted) return;
    switch (command) {
      case 'reset':
        _resetScroll();
        break;
      case 'rewind':
        if (_settings.scrollMode == ScrollMode.movieCredits) {
          setState(() {
            _movieCreditsOffset = (_movieCreditsOffset - 200).clamp(0.0, double.infinity);
          });
        } else if (_scrollController.hasClients) {
          _scrollController.animateTo(
            (_scrollController.offset - 200).clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        break;
      case 'forward':
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.offset + 200,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        break;
    }
  }

  Future<void> _setupDesktopWindow() async {
    await windowManager.setFullScreen(true);
  }

  Future<void> _toggleAlwaysOnTop() async {
    if (_isDesktop) {
      _isAlwaysOnTop = !_isAlwaysOnTop;
      await windowManager.setAlwaysOnTop(_isAlwaysOnTop);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollProgressTimer?.cancel();
    _scrollController.dispose();
    _settings.removeListener(_onRemoteSettingsChanged);
    _remoteCommandSub?.cancel();
    // Notify web clients fullscreen stopped
    try {
      final remoteService = Provider.of<RemoteServerService>(context, listen: false);
      remoteService.broadcastDisplayState(mode: 'fullscreen', isActive: false);
    } catch (_) {}
    // Restore system UI on mobile
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    // Restore window on desktop
    if (_isDesktop) {
      windowManager.removeListener(this);
      windowManager.setFullScreen(false);
      windowManager.setAlwaysOnTop(false);
    }
    super.dispose();
  }

  void _startScrolling() {
    _scrollTimer?.cancel();
    if (!_isPlaying) {
      setState(() {
        _isPlaying = true;
      });
      // Sync to settings for remote clients
      _suppressSettingsSync = true;
      _settings.setPlaying(true);
      _suppressSettingsSync = false;
    }
    
    final settings = Provider.of<PrompterSettings>(context, listen: false);
    
    if (settings.scrollMode == ScrollMode.movieCredits) {
      // Movie Credits mode: animate offset for 3-line viewport
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (_isPlaying) {
          setState(() {
            _movieCreditsOffset += _currentSpeed / 60.0;
            if (_mcCycleHeight > 0 && _movieCreditsOffset >= _mcCycleHeight) {
              _movieCreditsOffset -= _mcCycleHeight;
            }
          });
        }
      });
    } else {
      // If already at end, reset to beginning before starting
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0 &&
          _scrollController.offset >= _scrollController.position.maxScrollExtent) {
        _scrollController.jumpTo(0);
      }
      // Regular vertical scroll
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (_scrollController.hasClients && _isPlaying) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          final currentScroll = _scrollController.offset;
          
          if (currentScroll >= maxScroll) {
            _pauseScrolling();
            return;
          }
          
          final pixelsPerFrame = _currentSpeed / 60.0;
          _scrollController.jumpTo(currentScroll + pixelsPerFrame);
        }
      });
    }
  }

  void _pauseScrolling() {
    _scrollTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
    // Sync to settings for remote clients
    _suppressSettingsSync = true;
    _settings.setPlaying(false);
    _suppressSettingsSync = false;
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _pauseScrolling();
    } else {
      _startScrolling();
    }
  }

  void _resetScroll() {
    final settings = Provider.of<PrompterSettings>(context, listen: false);
    if (settings.scrollMode == ScrollMode.movieCredits) {
      setState(() {
        _movieCreditsOffset = 0.0;
      });
    } else {
      _scrollController.jumpTo(0);
    }
    if (!_isPlaying) {
      _startScrolling();
    }
  }

  void _adjustSpeed(double delta) {
    setState(() {
      _currentSpeed = (_currentSpeed + delta).clamp(10.0, 200.0);
    });
  }

  /// Apply initial scroll progress (used when resuming from another mode)
  void _applyInitialProgress(double progress) {
    final settings = Provider.of<PrompterSettings>(context, listen: false);
    if (settings.scrollMode == ScrollMode.movieCredits) {
      // Will be applied after layout computes _mcCycleHeight
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mcCycleHeight > 0) {
          setState(() {
            _movieCreditsOffset = progress * _mcCycleHeight;
          });
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          final max = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(max * progress);
        }
      });
    }
  }

  /// Periodically broadcast scroll progress to web remote preview (~4 Hz)
  void _startScrollProgressBroadcast() {
    _scrollProgressTimer?.cancel();
    _scrollProgressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final remoteService = Provider.of<RemoteServerService>(context, listen: false);
      if (!remoteService.isRunning) return;

      double progress = 0.0;
      final settings = Provider.of<PrompterSettings>(context, listen: false);
      if (settings.scrollMode == ScrollMode.movieCredits) {
        progress = _mcCycleHeight > 0 ? (_movieCreditsOffset % _mcCycleHeight) / _mcCycleHeight : 0.0;
      } else if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        progress = max > 0 ? _scrollController.offset / max : 0.0;
      }
      remoteService.broadcastScrollProgress(progress, mode: 'fullscreen');
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  TextStyle _getTextStyle(PrompterSettings settings) {
    try {
      return GoogleFonts.getFont(
        settings.fontFamily,
        fontSize: settings.fontSize,
        fontWeight: settings.isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: settings.isItalic ? FontStyle.italic : FontStyle.normal,
        color: settings.textColor,
        height: settings.lineHeight,
      );
    } catch (e) {
      return TextStyle(
        fontSize: settings.fontSize,
        fontWeight: settings.isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: settings.isItalic ? FontStyle.italic : FontStyle.normal,
        color: settings.textColor,
        height: settings.lineHeight,
      );
    }
  }

  Widget _buildMovieCreditsContent(PrompterSettings settings, TextStyle textStyle) {
    // Convert multi-line text to single continuous line for horizontal scrolling
    final singleLineText = '${settings.text.replaceAll('\n', '     ')}     ';

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scale(settings.mirrorHorizontal ? -1.0 : 1.0, 1.0, 1.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lineWidth = constraints.maxWidth - settings.paddingHorizontal * 2;

          // Measure single line height
          final linePainter = TextPainter(
            text: TextSpan(text: 'Ág', style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          final lineHeight = linePainter.height;

          // Measure text width as single horizontal line
          final textPainter = TextPainter(
            text: TextSpan(text: singleLineText, style: textStyle),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();
          final textWidth = textPainter.width;

          _mcCycleHeight = textWidth; // cycle = one full text width
          if (textWidth <= 0) return const SizedBox();

          final effectiveOffset = _movieCreditsOffset % textWidth;
          final copies = (3 * lineWidth / textWidth).ceil() + 2;
          final repeatedText = List.generate(copies, (_) => singleLineText).join();

          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: settings.paddingHorizontal),
              child: SizedBox(
                height: constraints.maxHeight * 0.5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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

  @override
  Widget build(BuildContext context) {
    return Consumer<PrompterSettings>(
      builder: (context, settings, child) {
        final textStyle = _getTextStyle(settings);

        return Scaffold(
          body: GestureDetector(
            onTap: _toggleControls,
            onDoubleTap: _togglePlayPause,
            onVerticalDragUpdate: (details) {
              // Manual scroll when dragging
              if (!_isPlaying) {
                _scrollController.jumpTo(
                  _scrollController.offset - details.delta.dy,
                );
              }
            },
            child: Stack(
              children: [
                // Main content
                Container(
                  color: Color.fromRGBO(
                    settings.backgroundColor.red,
                    settings.backgroundColor.green,
                    settings.backgroundColor.blue,
                    settings.opacity,
                  ),
                  width: double.infinity,
                  height: double.infinity,
                  child: settings.scrollMode == ScrollMode.movieCredits
                      ? _buildMovieCreditsContent(settings, textStyle)
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..scale(settings.mirrorHorizontal ? -1.0 : 1.0, 1.0, 1.0),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.symmetric(
                              horizontal: settings.paddingHorizontal,
                              vertical: MediaQuery.of(context).size.height / 3,
                            ),
                            child: Text(
                              settings.text,
                              style: textStyle,
                              textAlign: settings.textAlign,
                            ),
                          ),
                        ),
                ),

                // Center line indicator
                Positioned(
                  top: MediaQuery.of(context).size.height / 3,
                  left: 0,
                  child: Container(
                    height: 2,
                    width: 50,
                    alignment: Alignment.centerRight,
                    child: Container(
                      color: Color.fromRGBO(
                        settings.textColor.red,
                        settings.textColor.green,
                        settings.textColor.blue,
                        0.5,
                      ),
                    ),
                  ),
                ),

                // Controls overlay
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControls(settings),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls(PrompterSettings settings) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color.fromRGBO(0, 0, 0, 0.7),
            Colors.transparent,
            Colors.transparent,
            const Color.fromRGBO(0, 0, 0, 0.7),
          ],
          stops: const [0.0, 0.15, 0.85, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDesktop)
                        IconButton(
                          onPressed: _toggleAlwaysOnTop,
                          icon: Icon(
                            _isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                            color: _isAlwaysOnTop ? Colors.blue : Colors.white,
                            size: 26,
                          ),
                          tooltip: 'Luôn hiển thị trên cùng',
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentSpeed.toInt()} px/s',
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: settings.toggleMirror,
                    icon: Icon(
                      Icons.flip,
                      color: settings.mirrorHorizontal ? Colors.blue : Colors.white,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Speed controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => _adjustSpeed(-10),
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white, size: 36),
                      ),
                      const SizedBox(width: 20),
                      const Text(
                        'Tốc độ',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: () => _adjustSpeed(10),
                        icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 36),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Playback controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _resetScroll,
                        icon: const Icon(Icons.replay, color: Colors.white, size: 40),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 50,
                          ),
                          iconSize: 50,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          // Jump forward
                          _scrollController.animateTo(
                            _scrollController.offset + 200,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        },
                        icon: const Icon(Icons.fast_forward, color: Colors.white, size: 40),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
