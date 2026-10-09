import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_whisper_speech_service.dart';
import '../application/live_recognition.dart';
import 'live_caption_card.dart';
import 'salin_components.dart';
import '../../../theme/salin_theme.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/data/local_translation_service.dart';
import '../../translation/domain/translation.dart';

enum _SalinPage { capture, languages, result }

class SpeechHomeScreen extends StatefulWidget {
  const SpeechHomeScreen({super.key, this.speech, this.translator, this.voice});
  final LocalWhisperSpeechService? speech;
  final TranslationService? translator;
  final SpeechOutput? voice;

  @override
  State<SpeechHomeScreen> createState() => _SpeechHomeScreenState();
}

class _SpeechHomeScreenState extends State<SpeechHomeScreen>
    with WidgetsBindingObserver {
  _SalinPage _page = _SalinPage.capture;
  bool _showSettings = false;
  final GlobalKey _captionKey = GlobalKey();
  final TextEditingController _transcriptEditor = TextEditingController();
  late final LocalWhisperSpeechService _speech;
  late final TranslationController _translation;
  LocalTranslationService? _localTranslation;
  StreamSubscription<double>? _translationDownload;
  bool _translationInstalled = false;
  bool _checkingTranslation = true;
  bool _installingTranslation = false;
  double? _translationProgress;
  String? _translationSetupError;
  bool _noiseSuppression = false;
  int? _translationRecording;
  String? _audioNotice;
  bool get _tagalogSource => _translation.source == TranslationLanguage.tagalog;
  StreamSubscription<int>? _recognitionProgressUpdates;
  StreamSubscription<LiveRecognitionSnapshot>? _liveSubscription;
  StreamSubscription<void>? _recordingEnded;
  LiveRecognitionSnapshot _live = const LiveRecognitionSnapshot();
  bool _liveEnabled = true;
  bool _cancelling = false;
  int _requestId = 0;
  Timer? _recordingTicker;
  Stopwatch? _recordingStopwatch;

  bool _cebuanoInstalled = false;
  bool _mixedSpeech = false;
  bool get _useCebuanoModel => !_tagalogSource || _mixedSpeech;
  bool get _canRecord => _useCebuanoModel ? _cebuanoInstalled : _modelInstalled;
  bool _preferAccuracy = false;
  bool _chooseInitialSpeechModel = true;
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
      _installingTranslation ||
      _cancelling;

  bool get _navigationLocked =>
      _loadingModel ||
      _recording ||
      _finishing ||
      _cancelling ||
      _installingModel ||
      _installingTranslation;

  @override
  void initState() {
    super.initState();
    _speech = widget.speech ?? LocalWhisperSpeechService();
    final translator = widget.translator ?? LocalTranslationService();
    if (translator is LocalTranslationService) _localTranslation = translator;
    _translation = TranslationController(
      translator: translator,
      voice: widget.voice ?? DeviceSpeechOutput(),
    )..addListener(_translationChanged);
    unawaited(_checkTranslation());
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

  void _translationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkTranslation() async {
    try {
      final installed = await _localTranslation?.isInstalled() ?? true;
      if (mounted) setState(() => _translationInstalled = installed);
    } on MissingPluginException {
      if (mounted) {
        _translationSetupError =
            'Offline translation and device voices currently require Android.';
      }
    } catch (error) {
      if (mounted) {
        _translationSetupError = 'Could not verify translation models: $error';
      }
    } finally {
      if (mounted) setState(() => _checkingTranslation = false);
    }
  }

  Future<void> _installTranslation() async {
    if (_busy || _localTranslation == null) return;
    setState(() {
      _installingTranslation = true;
      _translationSetupError = null;
      _translationProgress = 0;
    });
    _translationDownload = _localTranslation!.downloadProgress.listen((
      fraction,
    ) {
      if (mounted) setState(() => _translationProgress = fraction);
    }, onError: (Object _) {});
    try {
      _speech.releaseModel();
      await _localTranslation!.install();
      if (mounted) setState(() => _translationInstalled = true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _translationSetupError = 'Translation setup failed: $error',
        );
      }
    } finally {
      await _translationDownload?.cancel();
      _translationDownload = null;
      if (mounted) setState(() => _installingTranslation = false);
    }
  }

  void _selectDirection(TranslationLanguage source) {
    if (_busy || source == _translation.source) return;
    _translation.selectSource(source);
    setState(() {
      _inputLanguage = source.voiceCode;
      _transcript = '';
      _rawTranscript = '';
      _audioNotice = null;
      _error = null;
      _recognitionDuration = null;
      _recordingDuration = Duration.zero;
    });
  }

  Future<void> _translate() async {
    if (_busy) return;
    _speech.releaseModel();
    await _translation.translate();
  }

  Future<void> _refreshModelStatus() async {
    try {
      _cebuanoInstalled = await _speech.findCebuanoModel() != null;
      if (_chooseInitialSpeechModel) {
        _chooseInitialSpeechModel = false;
        final base = await _speech.findInstalledModel(preferAccuracy: true);
        if (!mounted) return;
        if (base?.uri.pathSegments.last == 'ggml-base-q5_1.bin') {
          _preferAccuracy = true;
        }
      }
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

  Future<void> _importCebuano() async {
    if (_busy) return;
    setState(() {
      _installingModel = true;
      _error = null;
    });
    try {
      _speech.releaseModel();
      await _speech.importCebuanoModel();
      await _refreshModelStatus();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _installingModel = false);
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
    if (!_canRecord || _busy) return;
    final requestId = ++_requestId;
    _live = const LiveRecognitionSnapshot();
    _stopRecordingClock(reset: true);
    setState(() {
      _loadingModel = true;
      _error = null;
      _transcript = '';
      _rawTranscript = '';
      _audioNotice = null;
      _recordingDuration = Duration.zero;
      _recognitionDuration = null;
      _recognitionProgress = null;
    });

    try {
      _translationRecording = await _translation.beginRecording();
      if (!mounted || requestId != _requestId) return;
      await _speech.startRecording(
        language: _inputLanguage,
        preferAccuracy: _preferAccuracy,
        livePreview: _liveEnabled && !_useCebuanoModel,
        noiseSuppression: _noiseSuppression,
        cebuano: _useCebuanoModel,
      );
      _resultModelLabel = _useCebuanoModel
          ? 'Cebuano Small'
          : (_preferAccuracy
                ? 'Whisper base'
                : (_fastModelInstalled ? 'Whisper tiny' : 'Whisper base'));
      if (!mounted || requestId != _requestId) {
        await _speech.cancelTranscription();
        return;
      }
      setState(() {
        _loadingModel = false;
        _recording = true;
        _audioNotice = _speech.noiseNotice;
      });
      _startRecordingClock();
      if (_liveEnabled && !_useCebuanoModel) {
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
      _translation.cancelRecording();
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
        _audioNotice = _speech.diagnostics.notice ?? _speech.noiseNotice;
      });
      if ((_inputLanguage == 'tl' || _inputLanguage == 'ceb') &&
          _translationRecording != null) {
        _speech.releaseModel();
        unawaited(
          _translation.acceptFinal(_translationRecording!, _transcript),
        );
      } else {
        _translation.cancelRecording();
      }
    } catch (error) {
      recognitionClock.stop();
      if (!mounted || requestId != _requestId) return;
      _translation.cancelRecording();
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
    _translation.cancelRecording();
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

  Future<void> _editTranscript({bool enterText = false}) async {
    final controller = _transcriptEditor;
    controller.text = enterText ? '' : _transcript;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          enterText
              ? 'Enter ${_translation.source.label} text'
              : 'Review transcription',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: enterText ? _translation.source.label : 'What you said',
          ),
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
    if (edited != null) {
      setState(() {
        _transcript = edited.trim();
        if (enterText) {
          _inputLanguage = _translation.source.voiceCode;
          _rawTranscript = '';
          _recordingDuration = Duration.zero;
          _recognitionDuration = null;
          _audioNotice = null;
        }
      });
      if (enterText || _inputLanguage == _translation.source.voiceCode) {
        _translation.edit(_transcript);
      }
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
    if (state == AppLifecycleState.paused) {
      unawaited(_translation.stopPlayback());
      if (_recording || _finishing || _loadingModel) {
        unawaited(_cancelRecording());
      }
    }
  }

  @override
  void dispose() {
    ++_requestId;
    _translation.removeListener(_translationChanged);
    _translation.dispose();
    _translationDownload?.cancel();
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
    final yellow = !_showSettings && _page == _SalinPage.languages;
    return PopScope(
      canPop:
          !_showSettings && _page == _SalinPage.capture && !_navigationLocked,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_navigationLocked) _goBack();
      },
      child: Scaffold(
        backgroundColor: yellow ? SalinTheme.yellow : Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: _showSettings ? 'Close settings' : 'Back',
                          onPressed: _navigationLocked ? null : _goBack,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        Expanded(
                          child: _showSettings
                              ? Text(
                                  'Speech & offline setup',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                )
                              : const SizedBox.shrink(),
                        ),
                        IconButton(
                          tooltip: 'Speech and offline settings',
                          onPressed: () =>
                              setState(() => _showSettings = !_showSettings),
                          icon: Icon(
                            _showSettings ? Icons.close : Icons.tune_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _showSettings
                        ? _buildSettings(colors)
                        : switch (_page) {
                            _SalinPage.capture => _buildCapture(colors),
                            _SalinPage.languages => _buildLanguageSelection(
                              colors,
                            ),
                            _SalinPage.result => _buildResult(colors),
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBack() {
    if (_showSettings) {
      setState(() => _showSettings = false);
    } else if (_page != _SalinPage.capture) {
      unawaited(_translation.stopPlayback());
      setState(() => _page = _SalinPage.capture);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _startAgain({bool done = false}) {
    if (_busy) return;
    _translation.edit(''); // Invalidates any outstanding translation/playback.
    setState(() {
      _transcript = '';
      _rawTranscript = '';
      _live = const LiveRecognitionSnapshot();
      _audioNotice = null;
      _error = null;
      _recordingDuration = Duration.zero;
      _recognitionDuration = null;
      _page = _SalinPage.capture;
    });
    if (done) {
      // Rebuild PopScope for the capture page before asking the route to pop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  Widget _buildCapture(ColorScheme colors) {
    final source = _inputLanguage == 'en'
        ? 'English'
        : _inputLanguage == 'auto'
        ? 'Auto-detected'
        : _translation.source.label;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: const PageStorageKey('capture'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    const SalinSteps(current: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 36, 28, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SalinLanguageHeading(language: source),
                                ),
                              ),
                              PopupMenuButton<TranslationLanguage>(
                                tooltip: 'Choose source language',
                                enabled: !_busy,
                                onSelected: _selectDirection,
                                itemBuilder: (_) => TranslationLanguage.values
                                    .map(
                                      (language) => PopupMenuItem(
                                        value: language,
                                        child: Text(language.label),
                                      ),
                                    )
                                    .toList(),
                                icon: const Icon(Icons.expand_more_rounded),
                              ),
                              IconButton(
                                tooltip: 'Swap languages and clear text',
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          _selectDirection(_translation.target),
                                icon: const Icon(Icons.swap_horiz_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: (constraints.maxHeight * .20).clamp(
                                100.0,
                                180.0,
                              ),
                            ),
                            child: KeyedSubtree(
                              key: _captionKey,
                              child:
                                  (_recording || _finishing) &&
                                      _liveEnabled &&
                                      !_useCebuanoModel
                                  ? LiveCaptionCard(
                                      snapshot: _live,
                                      finalizing: _finishing,
                                    )
                                  : _transcript.isNotEmpty
                                  ? SelectableText(
                                      _transcript,
                                      key: const PageStorageKey(
                                        'capture-transcript-text',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w700,
                                            height: 1.6,
                                          ),
                                    )
                                  : Text(
                                      _recording
                                          ? 'Recording locally. Tap Finish when you’re ready.'
                                          : _finishing
                                          ? 'Recognizing speech…'
                                          : 'Tap the microphone\nand say something.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: SalinTheme.muted,
                                            height: 1.5,
                                          ),
                                    ),
                            ),
                          ),
                          if (_transcript.isNotEmpty) ...[
                            Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: 'Edit transcription',
                                  onPressed: _busy ? null : _editTranscript,
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Copy transcription',
                                  onPressed: _copyTranscript,
                                  icon: const Icon(Icons.copy_rounded),
                                ),
                              ],
                            ),
                            const Text(
                              'Review names and unclear words before using this text.',
                              style: TextStyle(
                                fontSize: 12,
                                color: SalinTheme.muted,
                              ),
                            ),
                          ],
                          if (_audioNotice != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_audioNotice!),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _buildError(colors),
                            ),
                          if (!_canRecord && !_checkingModel) ...[
                            const SizedBox(height: 12),
                            Text(
                              _useCebuanoModel
                                  ? 'Import the Cebuano speech model in settings to record, or enter text.'
                                  : 'Install the speech model in settings to record, or enter text.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: SalinTheme.muted,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _showSettings = true),
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Set up offline speech'),
                            ),
                          ],
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _editTranscript(enterText: true),
                            icon: const Icon(Icons.keyboard_outlined),
                            label: Text(
                              'Enter ${_translation.source.label} text',
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  _busy || _translation.transcript.isEmpty
                                  ? null
                                  : () => setState(
                                      () => _page = _SalinPage.languages,
                                    ),
                              child: const Text('Translate'),
                            ),
                          ),
                          if (_inputLanguage != 'tl' && _inputLanguage != 'ceb')
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'This recognition mode does not translate. Select Tagalog or Bisaya to translate.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [const SalinWaveform(), _buildRecorderControls()],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecorderControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          if (_recording) ...[
            const SizedBox(height: 16),
            Text(
              _formatDuration(_recordingDuration),
              style: const TextStyle(
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Listening · up to 5 minutes',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelling ? null : _cancelRecording,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _cancelling ? null : _stopRecording,
                    style: FilledButton.styleFrom(
                      backgroundColor: SalinTheme.yellow,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Finish'),
                  ),
                ),
              ],
            ),
          ] else if (_loadingModel || _finishing || _cancelling) ...[
            const SizedBox(height: 24),
            if (_finishing)
              LinearProgressIndicator(value: _recognitionProgress)
            else
              const CircularProgressIndicator(color: SalinTheme.yellow),
            const SizedBox(height: 12),
            Text(
              _cancelling
                  ? 'Cancelling…'
                  : _loadingModel
                  ? 'Loading speech model…'
                  : 'Recognizing locally ${((_recognitionProgress ?? 0) * 100).round()}%',
              style: const TextStyle(color: Colors.white),
            ),
            if (!_cancelling)
              TextButton(
                onPressed: _cancelRecording,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(_finishing ? 'Cancel recognition' : 'Cancel'),
              ),
          ] else ...[
            Transform.translate(
              offset: const Offset(0, -12),
              child: SizedBox(
                width: 104,
                height: 104,
                child: IconButton.filled(
                  tooltip: 'Start recording',
                  onPressed: !_canRecord || _busy ? null : _startRecording,
                  style: IconButton.styleFrom(
                    backgroundColor: SalinTheme.yellow,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF484848),
                    disabledForegroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.black, width: 5),
                  ),
                  icon: const Icon(Icons.mic_none_rounded, size: 56),
                ),
              ),
            ),
            Text(
              _checkingModel
                  ? 'Checking speech model…'
                  : _canRecord
                  ? 'Tap to speak'
                  : 'Set up speech to record',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLanguageSelection(ColorScheme colors) {
    return ListView(
      key: const PageStorageKey('languages'),
      children: [
        const SizedBox(height: 4),
        const SalinSteps(current: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 52, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose Translation',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 30),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _translation.target.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                trailing: const Icon(Icons.west_rounded, size: 40),
                selected: true,
                selectedColor: Colors.black,
              ),
              const SizedBox(height: 10),
              Text(
                'From ${_translation.source.label}. More languages are not available offline yet.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 140),
              if (!_translationInstalled ||
                  _checkingTranslation ||
                  _translationSetupError != null)
                _buildTranslationSetup(colors),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    _busy ||
                        _checkingTranslation ||
                        !_translationInstalled ||
                        _translation.transcript.isEmpty
                    ? null
                    : () {
                        setState(() => _page = _SalinPage.result);
                        // Finish already translates finalized speech. Reuse that job/result.
                        if (!_translation.translating &&
                            _translation.translated.isEmpty) {
                          unawaited(_translate());
                        }
                      },
                child: const Text('Translate'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(ColorScheme colors) {
    return ListView(
      key: const PageStorageKey('result'),
      padding: const EdgeInsets.fromLTRB(28, 120, 28, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SalinLanguageHeading(language: _translation.target.label),
        ),
        const SizedBox(height: 24),
        if (_translation.translating) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text('Translating to ${_translation.target.label} on this device…'),
        ] else if (_translation.translated.isNotEmpty)
          SelectableText(
            _translation.translated,
            key: const PageStorageKey('translated-text'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.6,
            ),
          )
        else
          const Text('Your translation will appear here.'),
        if (_translation.error != null) ...[
          const SizedBox(height: 16),
          Text(_translation.error!, style: TextStyle(color: colors.error)),
          TextButton.icon(
            onPressed:
                _busy || _translation.translating || !_translationInstalled
                ? null
                : _translate,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry translation'),
          ),
        ],
        const SizedBox(height: 88),
        if (_translation.translated.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Copy translation',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _translation.translated),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Translation copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 28),
              ),
              TextButton.icon(
                onPressed: _translation.playing
                    ? _translation.stopPlayback
                    : _translation.play,
                icon: Icon(
                  _translation.playing
                      ? Icons.stop_rounded
                      : Icons.volume_up_outlined,
                ),
                label: Text(
                  _translation.playing ? 'Stop playback' : 'Play translation',
                ),
              ),
            ],
          ),
          if (_translation.voiceNotice != null) Text(_translation.voiceNotice!),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : () => _startAgain(done: true),
          child: const Text('Done'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _startAgain,
          style: FilledButton.styleFrom(
            backgroundColor: SalinTheme.yellow,
            foregroundColor: Colors.black,
          ),
          child: const Text('Translate Again'),
        ),
        const SizedBox(height: 24),
        if (_translation.translated.isNotEmpty)
          const Text(
            'Review meaning, names and numbers. This model can omit or mistranslate details.',
            style: TextStyle(
              fontSize: 12,
              color: SalinTheme.muted,
              height: 1.5,
            ),
          ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: const PageStorageKey('result-source-details'),
          tilePadding: EdgeInsets.zero,
          title: Text('Source · ${_translation.source.label}'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                _transcript,
                key: const PageStorageKey('result-source-text'),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Edit transcription',
                  onPressed: _busy
                      ? null
                      : () async {
                          await _editTranscript();
                          if (mounted) {
                            setState(() => _page = _SalinPage.capture);
                          }
                        },
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Copy transcription',
                  onPressed: _copyTranscript,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTranslationSetup(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_checkingTranslation) ...[
          const LinearProgressIndicator(),
          const Text('Checking translation model…'),
        ] else if (!_translationInstalled || _installingTranslation) ...[
          const Text(
            'Install offline translation · about 900 MB. NLLB research model, for noncommercial use. Setup needs internet and free storage.',
          ),
          const SizedBox(height: 12),
          if (_installingTranslation) ...[
            LinearProgressIndicator(value: _translationProgress),
            Text(
              'Installing translation ${((_translationProgress ?? 0) * 100).round()}%',
            ),
          ] else
            FilledButton.icon(
              onPressed: _busy ? null : _installTranslation,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Install translation model'),
            ),
        ] else
          const Text('Offline translation model installed.'),
        if (_translationSetupError != null)
          Text(_translationSetupError!, style: TextStyle(color: colors.error)),
      ],
    );
  }

  Widget _buildSettings(ColorScheme colors) {
    return ListView(
      key: const PageStorageKey('settings'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        if (_tagalogSource)
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(_inputLanguage),
            initialValue: _inputLanguage,
            decoration: const InputDecoration(
              labelText: 'Recognition language',
            ),
            items: const [
              DropdownMenuItem(value: 'tl', child: Text('Tagalog / Filipino')),
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(
                value: 'auto',
                child: Text(
                  'Auto-detect · experimental',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) {
                      _translation.edit('');
                      setState(() {
                        _inputLanguage = value;
                        _transcript = '';
                        _rawTranscript = '';
                      });
                    }
                  },
          ),
        const SizedBox(height: 8),
        Text(
          _tagalogSource
              ? 'English and auto-detect remain recognition-only modes. Use Tagalog input for automatic translation.'
              : (_cebuanoInstalled
                    ? 'Cebuano voice uses the trained Small model after Finish. English mixing is experimental; recognition takes longer.'
                    : 'Import the Cebuano speech model to enable voice input, or enter Cebuano text below.'),
          style: const TextStyle(fontSize: 12, color: Color(0xFF626262)),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _editTranscript(enterText: true),
          icon: const Icon(Icons.keyboard_outlined),
          label: Text('Enter ${_translation.source.label} text'),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          title: const Text('Live captions'),
          subtitle: const Text(
            'Words appear as recognition completes. Uses more battery.',
          ),
          value: _liveEnabled && !_useCebuanoModel,
          onChanged: _busy || _useCebuanoModel
              ? null
              : (value) => setState(() => _liveEnabled = value),
        ),
        SwitchListTile(
          title: const Text('Reduce background noise · experimental'),
          subtitle: const Text(
            'Uses device suppression when available. Off preserves the original audio path; compare results on your phone.',
          ),
          value: _noiseSuppression,
          onChanged: _busy
              ? null
              : (value) => setState(() => _noiseSuppression = value),
        ),
        SwitchListTile(
          title: const Text('Refine with Whisper Base'),
          subtitle: const Text(
            'Selected when Base is installed. Uses Tiny for live text and Base after Finish. More accurate in our Tagalog samples, but slower.',
          ),
          value: _preferAccuracy && !_useCebuanoModel,
          onChanged: _busy || _useCebuanoModel
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
        SwitchListTile(
          title: const Text('Cebuano / mixed speech · experimental'),
          subtitle: Text(
            _cebuanoInstalled
                ? 'Uses Cebuano Small after Finish. Cebuano–English is the training focus; Tagalog mixing is not yet validated.'
                : 'Requires the converted 190 MB research model. Import it below.',
          ),
          value: _useCebuanoModel,
          onChanged: _busy || !_tagalogSource || !_cebuanoInstalled
              ? null
              : (value) => setState(() => _mixedSpeech = value),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _importCebuano,
          icon: const Icon(Icons.file_open_outlined),
          label: Text(
            _cebuanoInstalled
                ? 'Replace Cebuano speech model'
                : 'Import Cebuano speech model',
          ),
        ),
        if (_tagalogSource &&
            !_useCebuanoModel &&
            (!_modelInstalled || _installingModel || _checkingModel))
          _buildModelCard(colors),

        const SizedBox(height: 24),
        Text(
          'Translation & playback',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _buildTranslationSetup(colors),
        const SizedBox(height: 12),
        const Text(
          'Playback uses an installed offline voice for the target language when available.',
        ),
        if (_error != null) _buildError(colors),
        if (_transcript.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Recording details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '$_resultModelLabel · ${_formatDuration(_recordingDuration)}'
            '${_recognitionDuration == null ? '' : ' · recognized in ${(_recognitionDuration!.inMilliseconds / 1000).toStringAsFixed(1)}s'}',
          ),
          if (_rawTranscript.isNotEmpty && _transcript != _rawTranscript.trim())
            ExpansionTile(
              title: const Text('Original recognition · edited above'),
              children: [
                SelectableText(
                  _rawTranscript,
                  key: const PageStorageKey('original-transcript-text'),
                ),
              ],
            ),
        ],
        const SizedBox(height: 24),
        _buildPrivacyNote(colors),
      ],
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
                    color: const Color(0xFFFFF4CF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.memory_rounded,
                    color: Color(0xFF000000),
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
                          color: Color(0xFF626262),
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
                style: TextStyle(color: Color(0xFF626262), fontSize: 12),
              ),
            ] else if (_installingModel) ...[
              const SizedBox(height: 17),
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 8),
              Text(
                _downloadProgress == null
                    ? 'Preparing download…'
                    : 'Downloading model ${(_downloadProgress! * 100).round()}%',
                style: const TextStyle(color: Color(0xFF626262), fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _installModel,
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
                style: TextStyle(color: Color(0xFF626262), fontSize: 12),
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

  Widget _buildPrivacyNote(ColorScheme colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: colors.primary),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Speech recognition and translation run on this device after model setup. Audio and text are not sent to a server.',
            style: TextStyle(
              color: Color(0xFF626262),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
