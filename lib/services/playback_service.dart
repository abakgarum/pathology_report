import 'package:audioplayers/audioplayers.dart';

enum PlaybackState { idle, playing, paused, stopped }

class PlaybackService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  PlaybackState _state = PlaybackState.idle;
  Duration _duration = Duration.zero;
  Duration _currentPosition = Duration.zero;
  String? _currentPlayingPath;

  // Getters
  PlaybackState get state => _state;
  Duration get duration => _duration;
  Duration get currentPosition => _currentPosition;
  String? get currentPlayingPath => _currentPlayingPath;
  bool get isPlaying => _state == PlaybackState.playing;

  // Public streams
  Stream<Duration> get onDurationChanged => _audioPlayer.onDurationChanged;
  Stream<Duration> get onPositionChanged => _audioPlayer.onPositionChanged;
  Stream<PlayerState> get onPlayerStateChanged =>
      _audioPlayer.onPlayerStateChanged;

  PlaybackService() {
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to duration changes
    _audioPlayer.onDurationChanged.listen((d) {
      _duration = d;
    });

    // Listen to position changes
    _audioPlayer.onPositionChanged.listen((p) {
      _currentPosition = p;
    });

    // Listen to state changes
    _audioPlayer.onPlayerStateChanged.listen((state) {
      switch (state) {
        case PlayerState.playing:
          _state = PlaybackState.playing;
          break;
        case PlayerState.paused:
          _state = PlaybackState.paused;
          break;
        case PlayerState.stopped:
          _state = PlaybackState.stopped;
          break;
        case PlayerState.completed:
          throw UnimplementedError();
        case PlayerState.disposed:
          // TODO: Handle this case.
          throw UnimplementedError();
      }
    });

    // Listen to completion
    _audioPlayer.onPlayerComplete.listen((_) {
      _state = PlaybackState.stopped;
      _currentPosition = Duration.zero;
    });
  }

  /// Play audio from file path (supports file://, absolute paths, or URLs)
  Future<void> play(String filePath) async {
    try {
      // Ensure file path is a proper file URL
      String sourcePath = filePath;
      if (!filePath.startsWith('file://')) {
        sourcePath = 'file://$filePath';
      }

      // If already playing this file, just resume
      if (_currentPlayingPath == filePath && _state == PlaybackState.paused) {
        await _audioPlayer.resume();
        _state = PlaybackState.playing;
        return;
      }

      // Otherwise, play new file
      _currentPlayingPath = filePath;
      _currentPosition = Duration.zero;
      await _audioPlayer.play(UrlSource(sourcePath));
      _state = PlaybackState.playing;
    } catch (e) {
      _state = PlaybackState.idle;
      rethrow;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _audioPlayer.pause();
    _state = PlaybackState.paused;
  }

  /// Resume playback
  Future<void> resume() async {
    await _audioPlayer.resume();
    _state = PlaybackState.playing;
  }

  /// Stop playback and reset
  Future<void> stop() async {
    await _audioPlayer.stop();
    _state = PlaybackState.stopped;
    _currentPosition = Duration.zero;
    _currentPlayingPath = null;
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  /// Forward by duration (default 15 seconds)
  Future<void> forward({Duration amount = const Duration(seconds: 15)}) async {
    final newPos = _currentPosition + amount;
    if (newPos < _duration) {
      await seek(newPos);
    } else {
      await seek(_duration);
    }
  }

  /// Backward by duration (default 15 seconds)
  Future<void> backward({Duration amount = const Duration(seconds: 15)}) async {
    final newPos = _currentPosition - amount;
    if (newPos > Duration.zero) {
      await seek(newPos);
    } else {
      await seek(Duration.zero);
    }
  }

  /// Set playback rate
  Future<void> setPlaybackRate(double rate) async {
    await _audioPlayer.setPlaybackRate(rate);
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
