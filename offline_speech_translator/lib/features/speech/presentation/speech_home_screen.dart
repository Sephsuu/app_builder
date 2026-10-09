import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_whisper_speech_service.dart';
import '../application/live_recognition.dart';
import 'live_caption_card.dart';

class SpeechHomeScreen extends StatefulWidget {
  const SpeechHomeScreen({super.key});

  @override
  State<SpeechHomeScreen> createState() => _SpeechHomeScreenState();
}

class _SpeechHomeScreenState extends State<SpeechHomeScreen>
    with WidgetsBindingObserver {
  final GlobalKey _captionKey = GlobalKey();
  final TextEditingController _transcriptEditor = TextEditingController();
  final LocalWhisperSpeechService _speech = LocalWhisperSpeechService();
  StreamSubscription<int>? _recognitionProgressUpdates;
  StreamSubscription<LiveRecognitionSnapshot>? _liveSubscription;
  StreamSubscription<void>? _recordingEnded;
  LiveRecognitionSnapshot _live = const LiveRecognitionSnapshot();
  bool _liveEnabled = true;
  bool _cancelling = false;
  int _requestId = 0;
  Timer? _recordingTicker;
  Stopwatch? _recordingStopwatch;

  bool _preferAccuracy = false;
  String _resultModelLabel = 'Whisper tiny';
  bool _checkingModel = true;
  bool _modelInstalled = false;
  bool _fastModelInstalled = false;
  bool _installingModel = false;
  bool _loadingModel = false;
  bool _recording = false;
  bool _finishing = false;
  double? _downloadProgress;
  String _inputLanguage = 'tl';
  String _transcript = '';
  String _rawTranscript = '';
  String? _error;
  Duration _recordingDuration = Duration.zero;
  Duration? _recognitionDuration;
  double? _recognitionProgress;

  bool get _busy =>
      _checkingModel ||
      _installingModel ||
      _loadingModel ||
      _recording ||
      _finishing ||
      _cancelling;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liveSubscription = _speech.liveUpdates.listen((snapshot) {
      if (!mounted || !_recording || _cancelling) return;
      setState(() => _live = snapshot);
    });
    _recordingEnded = _speech.recordingEnded.listen((_) {
      if (mounted && _recording && !_cancelling) unawaited(_stopRecording());
    });
    _recognitionProgressUpdates = _speech.recognitionProgress.listen((
      progress,
    ) {
      if (!mounted || !_finishing) return;
      setState(() => _recognitionProgress = progress / 100);
    });
    _refreshModelStatus();
  }

  Future<void> _refreshModelStatus() async {
    try {
      final file = await _speech.findInstalledModel(
        preferAccuracy: _preferAccuracy,
      );
      if (!mounted) return;
      final fastModelInstalled =
          file?.uri.pathSegments.last ==
          LocalWhisperSpeechService.modelFileName;
      setState(() {
        _modelInstalled = file != null;
        _fastModelInstalled = fastModelInstalled;
        _checkingModel = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _modelInstalled = false;
        _fastModelInstalled = false;
        _checkingModel = false;
        _error =
            'The saved speech model could not be verified. Install it again.';
      });
    }
  }

  Future<void> _installModel() async {
    if (_installingModel || _recording || _loadingModel || _finishing) return;
    setState(() {
      _installingModel = true;
      _error = null;
      _downloadProgress = 0;
    });

    try {
      await for (final progress in _speech.installModel(
        preferAccuracy: _preferAccuracy,
      )) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress.fraction);
      }
      final file = await _speech.findInstalledModel(
        preferAccuracy: _preferAccuracy,
      );
      if (file == null) throw StateError('The model download did not finish.');
      if (!mounted) return;
      setState(() {
        _modelInstalled = true;
        _fastModelInstalled =
            file.uri.pathSegments.last ==
            LocalWhisperSpeechService.modelFileName;
        _installingModel = false;
        _downloadProgress = 1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installingModel = false;
        _error = _friendlyError(error, whileInstalling: true);
      });
    }
  }

  Future<void> _startRecording() async {
    if (!_modelInstalled || _busy) return;
    final requestId = ++_requestId;
    _live = const LiveRecognitionSnapshot();
    _stopRecordingClock(reset: true);
    setState(() {
      _loadingModel = true;
      _error = null;
      _transcript = '';
      _recordingDuration = Duration.zero;
      _recognitionDuration = null;
      _recognitionProgress = null;
    });

    try {
      await _speech.startRecording(
        language: _inputLanguage,
        preferAccuracy: _preferAccuracy,
        livePreview: _liveEnabled,
      );
      _resultModelLabel = _fastModelInstalled ? 'Whisper tiny' : 'Whisper base';
      if (!mounted || requestId != _requestId) {
        await _speech.cancelTranscription();
        return;
      }
      setState(() {
        _loadingModel = false;
        _recording = true;
      });
      _startRecordingClock();
      if (_liveEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final captionContext = _captionKey.currentContext;
          if (mounted && _recording && captionContext != null) {
            unawaited(
              Scrollable.ensureVisible(
                captionContext,
                alignment: 0.3,
                duration: const Duration(milliseconds: 180),
              ),
            );
          }
        });
      }
    } catch (error) {
      _stopRecordingClock(reset: true);
      await _speech.cancelTranscription();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingModel = false;
        _recording = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _finishing || _cancelling) return;
    _stopRecordingClock();
    setState(() {
      _recording = false;
      _finishing = true;
      _error = null;
      _recognitionProgress = 0;
    });
    final requestId = _requestId;
    final recognitionClock = Stopwatch()..start();
    try {
      final result = await _speech.stopRecordingAndTranscribe();
      recognitionClock.stop();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _rawTranscript = result.text;
        _transcript = result.text.trim();
        if (_transcript.isEmpty) {
          _error = 'No clear speech was recognized. Please try again.';
        }
        _recognitionDuration = recognitionClock.elapsed;
        _recognitionProgress = 1;
        _finishing = false;
      });
    } catch (error) {
      recognitionClock.stop();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _finishing = false;
        _recognitionDuration = recognitionClock.elapsed;
        _recognitionProgress = null;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _cancelRecording() async {
    if (_cancelling || (!_recording && !_loadingModel && !_finishing)) return;
    ++_requestId;
    _stopRecordingClock(reset: true);
    setState(() => _cancelling = true);
    Object? cancellationError;
    try {
      await _speech.cancelTranscription();
    } catch (error) {
      cancellationError = error;
    } finally {
      if (mounted) {
        setState(() {
          _cancelling = false;
          _recording = false;
          _loadingModel = false;
          _finishing = false;
          _transcript = '';
          _error = cancellationError == null
              ? null
              : _friendlyError(cancellationError);
          _live = const LiveRecognitionSnapshot();
          _recordingDuration = Duration.zero;
          _recognitionDuration = null;
          _recognitionProgress = null;
        });
      }
    }
  }

  void _startRecordingClock() {
    _recordingTicker?.cancel();
    final stopwatch = Stopwatch()..start();
    _recordingStopwatch = stopwatch;
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording) return;
      setState(() => _recordingDuration = stopwatch.elapsed);
    });
  }

  void _stopRecordingClock({bool reset = false}) {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    _recordingStopwatch?.stop();
    if (reset) {
      _recordingStopwatch = null;
      _recordingDuration = Duration.zero;
    } else if (_recordingStopwatch != null) {
      _recordingDuration = _recordingStopwatch!.elapsed;
    }
  }

  String _friendlyError(Object error, {bool whileInstalling = false}) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission') || message.contains('denied')) {
      return 'Microphone access is needed. Allow it in Android Settings, then try again.';
    }
    if (whileInstalling ||
        message.contains('socket') ||
        message.contains('network')) {
      return 'Could not install the model. Connect to Wi-Fi and try again.';
    }
    return 'Speech recognition could not start. ${error.toString()}';
  }

  Future<void> _editTranscript() async {
    final controller = _transcriptEditor;
    controller.text = _transcript;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review transcription'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'What you said'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (edited != null && edited.trim().isNotEmpty) {
      setState(() => _transcript = edited.trim());
    }
  }

  Future<void> _copyTranscript() async {
    if (_transcript.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _transcript));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Transcription copied')));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && (_recording || _finishing)) {
      unawaited(_cancelRecording());
    }
  }

  @override
  void dispose() {
    ++_requestId;
    WidgetsBinding.instance.removeObserver(this);
    _liveSubscription?.cancel();
    _recordingEnded?.cancel();
    _transcriptEditor.dispose();
    _recordingTicker?.cancel();
    _recordingStopwatch?.stop();
    _recognitionProgressUpdates?.cancel();
    unawaited(_speech.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(colors)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              sliver: SliverList.list(
                children: [
                  _buildIntro(),
                  const SizedBox(height: 20),
                  _buildLanguageCard(colors),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _inputLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Recognition language',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'tl',
                        child: Text('Tagalog / Filipino'),
                      ),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text('Auto-detect · experimental'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _inputLanguage = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cebuano / Bisaya recognition needs a separate validated model. '
                    'Auto-detect does not add support for every Philippine language.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF71807A)),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    title: const Text('Live captions'),
                    subtitle: const Text(
                      'Words appear as recognition completes. Uses more battery.',
                    ),
                    value: _liveEnabled,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _liveEnabled = value),
                  ),
                  SwitchListTile(
                    title: const Text('Refine with Whisper Base'),
                    subtitle: const Text(
                      'Fast model for live text; larger model reviews after Finish. Requires both downloads for fastest previews.',
                    ),
                    value: _preferAccuracy,
                    onChanged: _busy
                        ? null
                        : (value) async {
                            setState(() {
                              _preferAccuracy = value;
                              _checkingModel = true;
                              _error = null;
                            });
                            await _refreshModelStatus();
                          },
                  ),
                  if (!_modelInstalled || _installingModel || _checkingModel)
                    _buildModelCard(colors),
                  if (_modelInstalled) _buildRecorderCard(colors),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _buildError(colors),
                  ],
                  if (_recording || _transcript.isNotEmpty || _finishing) ...[
                    const SizedBox(height: 18),
                    KeyedSubtree(
                      key: _captionKey,
                      child: _buildTranscriptCard(colors),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildTranslationPlaceholder(colors),
                  const SizedBox(height: 22),
                  _buildPrivacyNote(colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F0E9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Color(0xFF187C70),
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sulti',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Voice translator',
                  style: TextStyle(fontSize: 12, color: Color(0xFF73817C)),
                ),
              ],
            ),
          ),
          _StatusBadge(
            icon: _modelInstalled
                ? Icons.verified_user_outlined
                : Icons.shield_outlined,
            label: _modelInstalled ? 'ASR LOCAL' : 'LOCAL AI',
            background: const Color(0xFFE5F3ED),
            foreground: colors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Make yourself\nunderstood.',
          style: TextStyle(
            color: Color(0xFF182C2A),
            fontSize: 34,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Speak Tagalog. Get closer in Cebuano.',
          style: TextStyle(color: Color(0xFF71807A), fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildLanguageCard(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _LanguageTile(
                label: 'FROM',
                language: _inputLanguage == 'tl'
                    ? 'Tagalog'
                    : _inputLanguage == 'en'
                    ? 'English'
                    : 'Auto-detect',
                code: _inputLanguage == 'tl'
                    ? 'FIL'
                    : _inputLanguage.toUpperCase(),
              ),
            ),
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5F1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.arrow_forward_rounded, color: colors.primary),
            ),
            const Expanded(
              child: _LanguageTile(
                label: 'TO',
                language: 'Bisaya',
                code: 'CEBUANO',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.memory_rounded,
                    color: Color(0xFF4A709A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _preferAccuracy
                            ? 'Install Whisper Base'
                            : 'Install speech recognition',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _preferAccuracy
                            ? 'About 60 MB. A larger multilingual model to compare with Tiny. Accuracy improvement is not yet measured; recognition may take longer.'
                            : 'One-time download · multilingual Whisper tiny · about 32 MB · faster, with some accuracy trade-off',
                        style: TextStyle(
                          color: Color(0xFF71807A),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_checkingModel) ...[
              const SizedBox(height: 17),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Checking installed models…',
                style: TextStyle(color: Color(0xFF71807A), fontSize: 12),
              ),
            ] else if (_installingModel) ...[
              const SizedBox(height: 17),
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 8),
              Text(
                _downloadProgress == null
                    ? 'Preparing download…'
                    : 'Downloading model ${(_downloadProgress! * 100).round()}%',
                style: const TextStyle(color: Color(0xFF71807A), fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _installModel,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    _preferAccuracy
                        ? 'Download Base model'
                        : 'Install speech model',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Connect once to download. Audio and recognition stay on this phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF71807A), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecorderCard(ColorScheme colors) {
    final recording = _recording;
    return Card(
      color: const Color(0xFF183C38),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Speech recording',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                _StatusBadge(
                  icon: recording
                      ? Icons.fiber_manual_record_rounded
                      : Icons.check_circle_outline_rounded,
                  label: recording
                      ? 'LISTENING'
                      : _loadingModel
                      ? 'STARTING'
                      : _finishing
                      ? 'TRANSCRIBING'
                      : 'READY',
                  background: recording
                      ? const Color(0xFF6B302D)
                      : const Color(0xFF285850),
                  foreground: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                recording
                    ? 'Speak naturally. Tap Finish when done · up to 5 minutes.'
                    : _finishing
                    ? 'Finishing the local transcription…'
                    : _loadingModel
                    ? 'Loading Whisper into memory. Recording starts next…'
                    : 'Your recording is processed on this phone.',
                style: const TextStyle(color: Color(0xFFC2D7D0), fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            if (recording) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _PulseDot(),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(_recordingDuration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_cancelling)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Cancelling…',
                  style: TextStyle(color: Colors.white),
                ),
              )
            else if (_loadingModel)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: Color(0xFF9FE2CC)),
              )
            else if (_finishing)
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        LinearProgressIndicator(value: _recognitionProgress),
                        const SizedBox(height: 8),
                        Text(
                          _recognitionProgress == null
                              ? 'Preparing local recognition…'
                              : 'Recognizing locally ${(_recognitionProgress! * 100).round()}%',
                          style: const TextStyle(
                            color: Color(0xFFC2D7D0),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _cancelRecording,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel recognition'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF74958C)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              )
            else if (recording)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cancelRecording,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF74958C)),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Finish'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD8F0E6),
                        foregroundColor: const Color(0xFF183C38),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              )
            else
              Semantics(
                button: true,
                label: 'Start recording',
                child: InkWell(
                  onTap: _startRecording,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD8F0E6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mic_none_rounded,
                      size: 35,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            if (!recording && !_loadingModel && !_finishing) ...[
              const SizedBox(height: 9),
              const Text(
                'Tap to speak',
                style: TextStyle(color: Color(0xFFC2D7D0), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF5D4C9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFA4513C),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFF733E32), height: 1.35),
            ),
          ),
          if (!_modelInstalled && !_installingModel)
            TextButton(onPressed: _installModel, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recognized speech',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_transcript.isNotEmpty && !_busy)
                  IconButton(
                    tooltip: 'Edit transcription',
                    onPressed: _editTranscript,
                    icon: const Icon(Icons.edit_outlined, size: 19),
                  ),
                if (_transcript.isNotEmpty)
                  IconButton(
                    tooltip: 'Copy transcription',
                    onPressed: _copyTranscript,
                    icon: const Icon(Icons.copy_rounded, size: 19),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if ((_recording || _finishing) && _liveEnabled)
              LiveCaptionCard(snapshot: _live, finalizing: _finishing)
            else if (_transcript.isEmpty && _finishing)
              const Text(
                'Recognizing speech…',
                style: TextStyle(color: Color(0xFF71807A), fontSize: 15),
              )
            else if (_transcript.isEmpty && _recording)
              const Text(
                'Recording locally. Speech is recognized after you tap Finish.',
                style: TextStyle(
                  color: Color(0xFF71807A),
                  fontSize: 14,
                  height: 1.45,
                ),
              )
            else
              Text(
                _transcript,
                style: const TextStyle(
                  color: Color(0xFF243A35),
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
            if (_transcript.isNotEmpty && !_busy) ...[
              const SizedBox(height: 8),
              const Text(
                'Review names and unclear words before using this text.',
              ),
              if (_transcript != _rawTranscript.trim())
                ExpansionTile(
                  title: const Text('Original recognition · edited above'),
                  children: [SelectableText(_rawTranscript)],
                ),
            ],
            const SizedBox(height: 10),
            Text(
              '$_resultModelLabel · ${_formatDuration(_recordingDuration)}'
              '${_recognitionDuration == null ? '' : ' · recognized in ${(_recognitionDuration!.inMilliseconds / 1000).toStringAsFixed(1)}s'}',
              style: const TextStyle(color: Color(0xFF89958F), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationPlaceholder(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bisaya · Cebuano',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'NEXT',
                    style: TextStyle(
                      color: Color(0xFF8A9690),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Translation and Cebuano voice are coming in the next build stage.',
              style: TextStyle(
                color: Color(0xFF7A8781),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StageChip(label: '1  Speech recognition', complete: true),
                _StageChip(label: '2  Translation', complete: false),
                _StageChip(label: '3  Spoken Cebuano', complete: false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNote(ColorScheme colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: colors.primary),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Speech recognition runs on this device after setup. Audio is not sent to a server.',
            style: TextStyle(
              color: Color(0xFF71807A),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.language,
    required this.code,
  });

  final String label;
  final String language;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8C9892),
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            language,
            style: const TextStyle(
              color: Color(0xFF203631),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            code,
            style: const TextStyle(
              color: Color(0xFF829089),
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.label, required this.complete});

  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final bg = complete ? const Color(0xFFE5F3ED) : const Color(0xFFF2F4F2);
    final fg = complete ? const Color(0xFF187C70) : const Color(0xFF8A9690);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: Color(0xFFFF8879),
        shape: BoxShape.circle,
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
