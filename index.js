import React from "react";
import { NativeModules, NativeEventEmitter, Platform, PermissionsAndroid } from "react-native";

const { Voice } = NativeModules;

// NativeEventEmitter is only availabe on React Native platforms, so this conditional is used to avoid import conflicts in the browser/server
const voiceEmitter = Platform.OS !== "web" ? new NativeEventEmitter(Voice) : null;

class RCTVoice {
  constructor() {
    this._loaded = false;
    this._listeners = null;
    this._events = {
      onSpeechStart: this._onSpeechStart.bind(this),
      onSpeechRecognized: this._onSpeechRecognized.bind(this),
      onSpeechEnd: this._onSpeechEnd.bind(this),
      onSpeechError: this._onSpeechError.bind(this),
      onSpeechResults: this._onSpeechResults.bind(this),
      onSpeechPartialResults: this._onSpeechPartialResults.bind(this),
      onSpeechVolumeChanged: this._onSpeechVolumeChanged.bind(this)
    };
  }

  rationale = {
    title: "Microphone Permission",
    message: "This app would like access to use your microphone."
  };

  defaultSpeechOptionsAndroid = {
    EXTRA_LANGUAGE_MODEL: "LANGUAGE_MODEL_FREE_FORM",
    EXTRA_MAX_RESULTS: 5,
    EXTRA_PARTIAL_RESULTS: true,
    REQUEST_PERMISSIONS_AUTO: true
  };

  /**
   * Updates the rationale
   *
   * @param {string} title
   * @param {string} message
   */
  setPermissionRationaleAndroid(title, message) {
    this.rationale = {
      title,
      message
    };
  }

  /**
   * Removes all event listeners. Use when unmounting your component.
   */
  removeAllListeners() {
    Voice.onSpeechStart = null;
    Voice.onSpeechRecognized = null;
    Voice.onSpeechEnd = null;
    Voice.onSpeechError = null;
    Voice.onSpeechResults = null;
    Voice.onSpeechPartialResults = null;
    Voice.onSpeechVolumeChanged = null;

    if (this._listeners) {
      this._listeners.map((listener, index) => listener.remove());
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
    try {
      await Voice.destroySpeech();
      if (this._listeners) {
        this.removeAllListeners();
      }
    } catch (error) {
      throw error;
    }
  }

  /**
   * Requests permissions to use the microphone.
   * Returns true if the user provided permissions
   */
  async requestPermissionsAndroid() {
    if (Platform.OS !== "android") {
      return true;
    }

    const result = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO, this.rationale);
    return result === true || result === PermissionsAndroid.RESULTS.GRANTED;
  }

  /**
   * Starts speech recognition
   * @param {string} locale Locale string
   * @param {object} options (Android) Additional options for speech recognition
   */
  async start(locale, options = {}) {
    if (!this._loaded && !this._listeners && voiceEmitter !== null) {
      this._listeners = Object.keys(this._events).map((key, index) => voiceEmitter.addListener(key, this._events[key]));
    }

    switch (Platform.OS) {
      case "ios":
        return await Voice.startSpeech(locale);
      case "android":
        // Returns "true" if the user already has permissions
        const hasPermissions = await this.requestPermissionsAndroid();
        if (!hasPermissions) {
          throw { code: "permissions" };
        }

        // Checks whether speech recognition is available on the device
        const isAvailable = await this.isAvailable();
        if (!isAvailable) {
          throw { code: "not_available" };
        }

        // Start speech recognition
        const speechOptions = {
          ...this.defaultSpeechOptionsAndroid,
          ...options
        };
        await Voice.startSpeech(locale, speechOptions);
      default:
        // Non-android & iOS devices are not supported
        throw { code: "not_available" };
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
    return await Voice.isSpeechAvailable();
  }

  /**
   * (iOS) Verifies that voice recognition is ready to be used
   */
  async isReady() {
    if (Platform.OS !== "ios") {
      return true;
    }
    return await Voice.isReady();
  }

  /**
   * Sets the iOS audio category.
   * @param {string} category "Ambient" | "SoloAmbient" | "Playback" | "Record" | "Record" | "PlayAndRecord" | "AudioProcessing" | "MultiRoute"
   * @param {boolean} mixWithOthers Enables: "AVAudioSessionCategoryOptionMixWithOthers"
   */
  setCategory(category, mixWithOthers = false) {
    if (Platform.OS !== "ios") return;
    Voice.setCategory(category, mixWithOthers);
  }

  async isRecognizing() {
    return await Voice.isRecognizing();
  }

  _onSpeechStart() {
    if (this.onSpeechStart) {
      this.onSpeechStart();
    }
  }
  _onSpeechRecognized(e) {
    if (this.onSpeechRecognized) {
      this.onSpeechRecognized(e);
    }
  }
  _onSpeechEnd(e) {
    if (this.onSpeechEnd) {
      this.onSpeechEnd(e);
    }
  }
  _onSpeechError(e) {
    if (this.onSpeechError) {
      this.onSpeechError(e);
    }
  }
  _onSpeechResults(e) {
    if (this.onSpeechResults) {
      this.onSpeechResults(e);
    }
  }
  _onSpeechPartialResults(e) {
    if (this.onSpeechPartialResults) {
      this.onSpeechPartialResults(e);
    }
  }
  _onSpeechVolumeChanged(e) {
    if (this.onSpeechVolumeChanged) {
      this.onSpeechVolumeChanged(e);
    }
  }
}

export default new RCTVoice();
