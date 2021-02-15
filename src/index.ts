import { NativeModules, NativeEventEmitter, Platform, PermissionsAndroid, Rationale } from 'react-native';

import invariant from 'invariant';

import {
  VoiceModule,
  SpeechEvents,
  SpeechRecognizedEvent,
  SpeechErrorEvent,
  SpeechResultsEvent,
  SpeechStartEvent,
  SpeechEndEvent,
  SpeechVolumeChangeEvent,
} from './VoiceModuleTypes';

const Voice = NativeModules.Voice as VoiceModule;

// NativeEventEmitter is only availabe on React Native platforms, so this conditional is used to avoid import conflicts in the browser/server
const voiceEmitter = Platform.OS !== 'web' ? new NativeEventEmitter(Voice) : null;
type SpeechEvent = keyof SpeechEvents;

class RCTVoice {
  _loaded: boolean;
  _listeners: any[] | null;
  _events: Required<SpeechEvents>;

  rationale: Rationale = {
    title: 'Microphone Permission',
    message: 'This app would like access to use your microphone.',
    buttonPositive: 'Accept',
  };

  constructor() {
    this._loaded = false;
    this._listeners = null;
    this._events = {
      onSpeechStart: () => {},
      onSpeechRecognized: () => {},
      onSpeechEnd: () => {},
      onSpeechError: () => {},
      onSpeechResults: () => {},
      onSpeechPartialResults: () => {},
      onSpeechVolumeChanged: () => {},
    };
  }

  removeAllListeners() {
    Voice.onSpeechStart = undefined;
    Voice.onSpeechRecognized = undefined;
    Voice.onSpeechEnd = undefined;
    Voice.onSpeechError = undefined;
    Voice.onSpeechResults = undefined;
    Voice.onSpeechPartialResults = undefined;
    Voice.onSpeechVolumeChanged = undefined;

    if (this._listeners) {
      this._listeners.map(listener => listener.remove());
      this._listeners = null;
    }
  }

  /**
   * Destroys the speech recognizer instance & removes all listeners
   */
  async destroy() {
    if (!this._loaded && !this._listeners) {
      return;
    }
    await Voice.destroySpeech();
    if (this._listeners) {
      this.removeAllListeners();
    }
  }

  /**
   * Requests permissions to use the microphone.
   * Returns true if the user provided permissions
   */
  async requestPermissionsAndroid() {
    if (Platform.OS !== 'android') {
      return true;
    }

    const result = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO, this.rationale);

    if (result !== 'granted') {
      throw { code: 'permissions' };
    }
    return true;
  }

  /**
   * Starts speech recognition
   * @param {string} locale Locale string
   * @param {object} options (Android) Additional options for speech recognition
   */
  async start(locale?: string, options = {}) {
    if (!this._loaded && !this._listeners && voiceEmitter !== null) {
      this._listeners = (Object.keys(this._events) as SpeechEvent[]).map((key: SpeechEvent) =>
        voiceEmitter.addListener(key, this._events[key]),
      );
    }

    switch (Platform.OS) {
      case 'ios':
        return Voice.startSpeech(locale);
      case 'android':
        // Returns "true" if the user already has permissions
        // throws { code: 'permissions' } if user denies permissions
        await this.requestPermissionsAndroid();

        // Checks whether speech recognition is available on the device
        const isAvailable = await this.isAvailable();
        if (!isAvailable) {
          throw { code: 'not_available' };
        }

        // Start speech recognition
        const speechOptions = {
          EXTRA_LANGUAGE_MODEL: 'LANGUAGE_MODEL_FREE_FORM',
          EXTRA_MAX_RESULTS: 5,
          EXTRA_PARTIAL_RESULTS: true,
          REQUEST_PERMISSIONS_AUTO: true,
          ...options,
        };
        return Voice.startSpeech(locale, speechOptions);
      default:
        // Non-android & iOS devices are not supported
        throw { code: 'not_available' };
    }
  }

  async stop() {
    if (!this._loaded && !this._listeners) {
      return;
    }
    // on Android this may throw an error
    await Voice.stopSpeech();
  }

  /**
   * Cancels speech recognition
   */
  async cancel() {
    if (!this._loaded && !this._listeners) {
      return;
    }
    // on Android this may throw an error
    await Voice.cancelSpeech();
  }

  /**
   * Verifies that voice recognition is available on the device
   */
  async isAvailable() {
    return Voice.isSpeechAvailable();
  }

  /**
   * (Android) Get a list of the speech recognition engines available on the device
   * */
  getSpeechRecognitionServices() {
    if (Platform.OS !== 'android') {
      invariant(Voice, 'Speech recognition services can be queried for only on Android');
      return;
    }

    return Voice.getSpeechRecognitionServices();
  }

  isRecognizing() {
    return Voice.isRecognizing();
  }

  set onSpeechStart(fn: (e: SpeechStartEvent) => void) {
    this._events.onSpeechStart = fn;
  }
  set onSpeechRecognized(fn: (e: SpeechRecognizedEvent) => void) {
    this._events.onSpeechRecognized = fn;
  }
  set onSpeechEnd(fn: (e: SpeechEndEvent) => void) {
    this._events.onSpeechEnd = fn;
  }
  set onSpeechError(fn: (e: SpeechErrorEvent) => void) {
    this._events.onSpeechError = fn;
  }
  set onSpeechResults(fn: (e: SpeechResultsEvent) => void) {
    this._events.onSpeechResults = fn;
  }
  set onSpeechPartialResults(fn: (e: SpeechResultsEvent) => void) {
    this._events.onSpeechPartialResults = fn;
  }
  set onSpeechVolumeChanged(fn: (e: SpeechVolumeChangeEvent) => void) {
    this._events.onSpeechVolumeChanged = fn;
  }
}

export {
  SpeechEndEvent,
  SpeechErrorEvent,
  SpeechEvents,
  SpeechStartEvent,
  SpeechRecognizedEvent,
  SpeechResultsEvent,
  SpeechVolumeChangeEvent,
};
export default new RCTVoice();
