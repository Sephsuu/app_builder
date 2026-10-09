import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_whisper_speech_service.dart';
import '../application/live_recognition.dart';
import 'live_caption_card.dart';
import 'conversation_widgets.dart';
import '../domain/audio_level.dart';
import '../../../theme/salin_theme.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/data/local_translation_service.dart';
import '../../translation/domain/translation.dart';

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
  bool _showSettings = false;
  final _audioEnvelope = AudioLevelEnvelope();
  List<double> _audioLevels = List.filled(36, 0);
  StreamSubscription<double>? _audioLevelUpdates;
  final GlobalKey _captionKey = GlobalKey();
  final GlobalKey _translationResultKey = GlobalKey();
  int _lastHistoryLength = 0;
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
  bool _reviewBeforeTranslation = false;
  bool _translateLinesSeparately = false;
  final Map<TranslationLanguage, _SpeechDraft> _speechDrafts = {};
  _SpeechDraft? _beforeRecording;
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
    _audioLevelUpdates = _speech.audioLevels.listen((rms) {
      if (!mounted || !_recording || _cancelling) return;
      setState(
        () => _audioLevels = [..._audioLevels.skip(1), _audioEnvelope.add(rms)],
      );
    });
    _refreshModelStatus();
  }

  void _translationChanged() {
    if (!mounted) return;
    final newTurn = _translation.history.length > _lastHistoryLength;
    _lastHistoryLength = _translation.history.length;
    setState(() {});
    if (newTurn && !_showSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final resultContext = _translationResultKey.currentContext;
        if (mounted && resultContext != null) {
          unawaited(
            Scrollable.ensureVisible(
              resultContext,
              alignment: .2,
              duration: const Duration(milliseconds: 180),
            ),
          );
        }
      });
    }
  }

  Future<void> _checkTranslation() async {
    if (mounted) {
      setState(() {
        _checkingTranslation = true;
        _translationSetupError = null;
      });
    }
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
    _speechDrafts[_translation.source] = _speechDraft;
    _translation.selectSource(source);
    setState(() {
      _restoreSpeechDraft(_speechDrafts[source]);
      _error = null;
      _live = const LiveRecognitionSnapshot();
    });
  }

  _SpeechDraft get _speechDraft => _SpeechDraft(
    transcript: _transcript,
    raw: _rawTranscript,
    language: _inputLanguage,
    model: _resultModelLabel,
    audioNotice: _audioNotice,
    recordingDuration: _recordingDuration,
    recognitionDuration: _recognitionDuration,
  );

  void _restoreSpeechDraft(_SpeechDraft? draft) {
    _inputLanguage = draft?.language ?? _translation.source.voiceCode;
    _transcript = draft?.transcript ?? '';
    _rawTranscript = draft?.raw ?? '';
    _resultModelLabel = draft?.model ?? '';
    _audioNotice = draft?.audioNotice;
    _recognitionDuration = draft?.recognitionDuration;
    _recordingDuration = draft?.recordingDuration ?? Duration.zero;
  }

  void _clearTurn() {
    if (_busy) return;
    _translation.clear();
    _speechDrafts.remove(_translation.source);
    setState(() {
      _restoreSpeechDraft(null);
      _error = null;
      _live = const LiveRecognitionSnapshot();
    });
  }

  Future<void> _translate() async {
    if (_busy) return;
    _speech.releaseModel();
    await _translation.translate(separateLines: _translateLinesSeparately);
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
    _beforeRecording = _speechDraft;
    final requestId = ++_requestId;
    _live = const LiveRecognitionSnapshot();
    _audioEnvelope.reset();
    _audioLevels = List.filled(36, 0);
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
    } catch (error) {
      _stopRecordingClock(reset: true);
      await _speech.cancelTranscription();
      if (!mounted || requestId != _requestId) return;
      _translation.cancelRecording();
      setState(() {
        _restoreSpeechDraft(_beforeRecording);
        _loadingModel = false;
        _recording = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _finishing || _cancelling) return;
    _stopRecordingClock();
    _audioEnvelope.reset();
    _audioLevels = List.filled(36, 0);
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
      if (_transcript.isEmpty) {
        _translation.cancelRecording();
        setState(() => _restoreSpeechDraft(_beforeRecording));
        return;
      }
      if ((_inputLanguage == 'tl' || _inputLanguage == 'ceb') &&
          _translationRecording != null) {
        _speech.releaseModel();
        unawaited(
          _translation.acceptFinal(
            _translationRecording!,
            _transcript,
            translateAutomatically:
                !_reviewBeforeTranslation && _translationInstalled,
            separateLines: _translateLinesSeparately,
          ),
        );
      } else {
        _translation.cancelRecording();
        _translation.clear();
      }
    } catch (error) {
      recognitionClock.stop();
      if (!mounted || requestId != _requestId) return;
      _translation.cancelRecording();
      setState(() {
        _restoreSpeechDraft(_beforeRecording);
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
          _restoreSpeechDraft(_beforeRecording);
          _error = cancellationError == null
              ? null
              : _friendlyError(cancellationError);
          _live = const LiveRecognitionSnapshot();
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
    _audioLevelUpdates?.cancel();
    unawaited(_speech.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final history = _translation.history.reversed.toList();
    return PopScope(
      canPop: !_navigationLocked && !_showSettings,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_navigationLocked && _showSettings) {
          setState(() => _showSettings = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  tooltip: _showSettings
                      ? 'Back to translator'
                      : 'Back to landing page',
                  onPressed: _navigationLocked
                      ? null
                      : () {
                          if (_showSettings) {
                            setState(() => _showSettings = false);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _showSettings ? 'Speech & offline setup' : 'Salin',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (!_showSettings)
                const Text(
                  'A conversation, in both languages',
                  style: TextStyle(fontSize: 12, color: SalinTheme.muted),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _showSettings
                  ? 'Close settings'
                  : 'Speech and offline settings',
              onPressed: () => setState(() => _showSettings = !_showSettings),
              icon: Icon(_showSettings ? Icons.close : Icons.tune_rounded),
            ),
          ],
        ),
        bottomNavigationBar:
            _recording || _finishing || _loadingModel || _cancelling
            ? _buildRecordingActions()
            : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _showSettings
                  ? _buildSettings(colors)
                  : CustomScrollView(
                      key: const PageStorageKey('conversation'),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LanguageSelection(
                                  source: _translation.source,
                                  enabled: !_busy,
                                  onSource: _selectDirection,
                                  onTarget: (language) =>
                                      _selectDirection(language.other),
                                  onSwap: () =>
                                      _selectDirection(_translation.target),
                                ),
                                const SizedBox(height: 12),
                                ConversationSteps(
                                  hasSource: _transcript.isNotEmpty,
                                  translating: _translation.translating,
                                  hasTranslation:
                                      _translation.translated.isNotEmpty,
                                  capturing:
                                      _recording || _loadingModel || _finishing,
                                ),
                                const SizedBox(height: 20),
                                _buildMicrophone(),
                                const SizedBox(height: 16),
                                if (!_canRecord && !_checkingModel) ...[
                                  Text(
                                    _useCebuanoModel
                                        ? 'Set up the Bisaya speech model to record, or type your message.'
                                        : 'Set up offline speech to record, or type your message.',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: SalinTheme.muted,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _showSettings = true,
                                          ),
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('Set up offline speech'),
                                  ),
                                ],
                                if (_error != null) ...[
                                  _buildError(colors),
                                  const SizedBox(height: 12),
                                ],
                                if (_audioNotice != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      _audioNotice!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                KeyedSubtree(
                                  key: _captionKey,
                                  child: TranslationTextPanel(
                                    title:
                                        'Original · ${_inputLanguage == 'en'
                                            ? 'English'
                                            : _inputLanguage == 'auto'
                                            ? 'Auto-detected'
                                            : _translation.source.label}',
                                    text: _transcript,
                                    placeholder: 'Your words appear here.',
                                    actions: [
                                      if (_transcript.isNotEmpty) ...[
                                        IconButton(
                                          tooltip: 'Clear current turn',
                                          onPressed: _busy ? null : _clearTurn,
                                          icon: const Icon(Icons.clear_rounded),
                                        ),
                                        IconButton(
                                          tooltip: 'Edit transcription',
                                          onPressed: _busy
                                              ? null
                                              : _editTranscript,
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        IconButton(
                                          tooltip: 'Copy transcription',
                                          onPressed: _copyTranscript,
                                          icon: const Icon(Icons.copy_rounded),
                                        ),
                                      ],
                                      TextButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () => _editTranscript(
                                                enterText: true,
                                              ),
                                        icon: const Icon(
                                          Icons.keyboard_outlined,
                                        ),
                                        label: Text(
                                          'Enter ${_translation.source.label} text',
                                        ),
                                      ),
                                    ],
                                    child:
                                        (_recording || _finishing) &&
                                            _liveEnabled &&
                                            !_useCebuanoModel
                                        ? LiveCaptionCard(
                                            snapshot: _live,
                                            finalizing: _finishing,
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TranslationTextPanel(
                                  key: _translationResultKey,
                                  title:
                                      '${_translation.restoredDraft && _translation.translated.isNotEmpty ? 'Saved translation' : 'Translation'} · ${_translation.target.label}',
                                  text: _translation.translated,
                                  placeholder: _translation.translating
                                      ? 'Translating on this device…'
                                      : 'The other language appears here.',
                                  accent: true,
                                  actions: [
                                    if (_translation.translated.isNotEmpty) ...[
                                      TextButton.icon(
                                        onPressed:
                                            _translation.playing &&
                                                _translation.playingEntryId ==
                                                    null
                                            ? _translation.stopPlayback
                                            : (_busy || _translation.playing
                                                  ? null
                                                  : () => _translation.play()),
                                        icon: Icon(
                                          _translation.playing &&
                                                  _translation.playingEntryId ==
                                                      null
                                              ? Icons.stop_rounded
                                              : Icons.volume_up_outlined,
                                        ),
                                        label: Text(
                                          _translation.playing &&
                                                  _translation.playingEntryId ==
                                                      null
                                              ? 'Stop playback'
                                              : 'Play translation',
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Copy translation',
                                        onPressed: () => _copyTranslation(
                                          _translation.translated,
                                        ),
                                        icon: const Icon(Icons.copy_rounded),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_translation.restoredDraft)
                                  const Text(
                                    'Saved for this direction. Translate again to request a new result.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: SalinTheme.muted,
                                    ),
                                  ),
                                if (_translation.error != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      _translation.error!,
                                      style: TextStyle(color: colors.error),
                                    ),
                                  ),
                                if (_translation.transcript.isNotEmpty &&
                                    !_recording &&
                                    !_finishing)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed:
                                          _busy ||
                                              _translation.translating ||
                                              !_translationInstalled
                                          ? null
                                          : _translate,
                                      icon: const Icon(Icons.translate_rounded),
                                      label: Text(
                                        _translation.error != null
                                            ? 'Retry translation'
                                            : 'Translate source text',
                                      ),
                                    ),
                                  ),
                                if (_translation.voiceNotice != null)
                                  Text(
                                    _translation.voiceNotice!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: SalinTheme.muted,
                                    ),
                                  ),
                                if (_translation.translated.isNotEmpty) ...[
                                  const Text(
                                    'Review meaning, names and numbers before using this translation.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: SalinTheme.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _canRecord && !_busy
                                        ? _startRecording
                                        : null,
                                    icon: const Icon(Icons.mic_rounded),
                                    label: const Text('Translate Again'),
                                  ),
                                ],
                                if (!_translationInstalled ||
                                    _checkingTranslation ||
                                    _translationSetupError != null) ...[
                                  const SizedBox(height: 16),
                                  _buildTranslationSetup(colors),
                                ],
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Conversation history',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                    Text(
                                      '${history.length} turns',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: SalinTheme.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  history.isEmpty
                                      ? 'Completed translations will appear here.'
                                      : 'Saved for this conversation session.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: SalinTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                          sliver: SliverList.builder(
                            itemCount: history.length,
                            itemBuilder: (context, index) {
                              final entry = history[index];
                              final playing =
                                  _translation.playing &&
                                  _translation.playingEntryId == entry.id;
                              return ConversationHistoryItem(
                                key: ValueKey(entry.id),
                                entry: entry,
                                playing: playing,
                                onPlay: playing
                                    ? _translation.stopPlayback
                                    : (_busy ||
                                              _translation.translating ||
                                              _translation.playing
                                          ? null
                                          : () => _translation.play(
                                              entry: entry,
                                            )),
                                onCopy: () =>
                                    _copyTranslation(entry.translated),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyTranslation(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Translation copied')));
    }
  }

  Widget _buildMicrophone() {
    final processing =
        _loadingModel ||
        _finishing ||
        _translation.translating ||
        _cancelling ||
        _translation.playing ||
        _checkingModel;
    final status = _cancelling
        ? 'Cancelling…'
        : _loadingModel
        ? 'Preparing the microphone…'
        : _recording
        ? 'Listening · ${_translation.source.label} · ${_formatDuration(_recordingDuration)}'
        : _finishing
        ? 'Transcribing on this device…'
        : _translation.translating
        ? 'Translating to ${_translation.target.label}…'
        : _translation.playing
        ? 'Playing offline speech…'
        : _checkingModel
        ? 'Checking installed speech models…'
        : _translation.error != null || _error != null
        ? 'Something went wrong. Try again below.'
        : _translation.translated.isNotEmpty
        ? (_translation.restoredDraft
              ? 'Saved translation ready to use.'
              : 'Translation ready. Your turn to speak.')
        : _transcript.isNotEmpty
        ? 'Review your source text, then translate.'
        : 'Tap to speak';
    return Column(
      children: [
        if (_recording) ...[
          AudioWaveform(levels: _audioLevels),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.fiber_manual_record,
                color: Color(0xFFBD2525),
                size: 14,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ] else ...[
          MicrophoneButton(
            enabled: _canRecord && !_busy,
            onPressed: _startRecording,
          ),
          const SizedBox(height: 16),
          ProcessingIndicator(
            label: status,
            processing: processing,
            progress: _finishing ? _recognitionProgress : null,
          ),
        ],
      ],
    );
  }

  Widget _buildRecordingActions() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _cancelling ? null : _cancelRecording,
              child: Text(_finishing ? 'Cancel recognition' : 'Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _recording && !_cancelling ? _stopRecording : null,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop'),
            ),
          ),
        ],
      ),
    ),
  );

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _translationSetupError!,
                style: TextStyle(color: colors.error),
              ),
              TextButton(
                onPressed: _checkingTranslation || _busy
                    ? null
                    : _checkTranslation,
                child: const Text('Retry model check'),
              ),
            ],
          ),
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
          title: const Text('Review before translating'),
          subtitle: const Text(
            'Check or edit the final transcript before requesting a translation.',
          ),
          value: _reviewBeforeTranslation,
          onChanged: _busy
              ? null
              : (value) => setState(() => _reviewBeforeTranslation = value),
        ),
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
        SwitchListTile(
          title: const Text('Translate each line separately'),
          subtitle: const Text(
            'For independent messages on separate lines. Can retain lines the model omits, but loses shared context and takes longer.',
          ),
          value: _translateLinesSeparately,
          onChanged: _busy || _translation.translating
              ? null
              : (value) => setState(() => _translateLinesSeparately = value),
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

class _SpeechDraft {
  const _SpeechDraft({
    required this.transcript,
    required this.raw,
    required this.language,
    required this.model,
    required this.audioNotice,
    required this.recordingDuration,
    required this.recognitionDuration,
  });
  final String transcript, raw, language, model;
  final String? audioNotice;
  final Duration recordingDuration;
  final Duration? recognitionDuration;
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
