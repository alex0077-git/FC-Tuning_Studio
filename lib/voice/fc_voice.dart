import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Short spoken cues for Tuning Studio.
/// Arm/disarm cues prefer loud assets under [assets/sounds/]; TTS is fallback only.
class FcVoice {
  FcVoice();

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  /// Master gate for every cue/TTS phrase. Default on; Connect page can flip it.
  bool enabled = true;
  bool _ready = false;

  /// Turns voice cues on/off. Off also stops any clip or TTS already playing.
  Future<void> setEnabled(bool value) async {
    enabled = value;
    if (value) return;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> init() async {
    if (_ready) return;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _tts.awaitSpeakCompletion(false);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.40);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      try {
        await _tts.setAudioAttributesForNavigation();
      } catch (_) {}
      _ready = true;
    } catch (_) {
      // Leave _ready false so the next cue retries init.
    }
  }

  Future<void> say(String phrase) async {
    if (!enabled) return;
    final text = phrase.trim();
    if (text.isEmpty) return;
    try {
      await init();
      if (!_ready) return;
      await _tts.setVolume(1.0);
      try {
        await _tts.setAudioAttributesForNavigation();
      } catch (_) {}
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  /// Transmitter / FC arm rising edge — play loud clip at max volume.
  Future<void> sayArmed() async {
    await _playCue('sounds/armed.mp3', 'Armed. Armed');
  }

  /// Transmitter / FC disarm falling edge — play loud clip at max volume.
  Future<void> sayDisarmed() async {
    await _playCue('sounds/disarmed.mp3', 'Disarmed. Disarmed');
  }

  /// Altitude hold engaged (ah_act rising edge).
  Future<void> sayAltHoldOn() async {
    await _playCue('sounds/althold_on.mp3', 'Altitude hold on.');
  }

  /// Altitude hold released (ah_act falling edge).
  Future<void> sayAltHoldOff() async {
    await _playCue('sounds/althold_off.mp3', 'Altitude hold off.');
  }

  /// Soft reboot accepted by FC (STATUSTEXT reset).
  Future<void> sayReset() async {
    await _playCue('sounds/reset.mp3', 'Reset.');
  }

  /// Battery first warning (caution threshold).
  Future<void> sayBatteryFirstWarning() async {
    await _playCue(
      'sounds/battery_first_warning.mp3',
      'Battery low. Plan to land.',
    );
  }

  /// Battery second warning (critical / must-land threshold).
  Future<void> sayBatterySecondWarning() async {
    await _playCue(
      'sounds/battery_second_warning.mp3',
      'Battery critical. Land now.',
    );
  }

  Future<void> _playCue(String assetPath, String ttsFallback) async {
    if (!enabled) return;
    try {
      await init();
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.play(AssetSource(assetPath));
    } catch (_) {
      await say(ttsFallback);
    }
  }

  Future<void> dispose() async {
    try {
      await _player.stop();
      await _player.dispose();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
