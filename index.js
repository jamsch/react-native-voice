import React, { NativeModules, NativeEventEmitter, Platform, PermissionsAndroid } from "react-native";

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

  async requestPermissionsAndroid() {
    if (Platform.OS !== "android") {
      return true;
    }

    const rationale = {
      title: "Microphone Permission",
      message: "This app needs access to your microphone."
    };

    const result = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO, rationale);
    return result === true || result === PermissionsAndroid.RESULTS.GRANTED;
  }

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
          EXTRA_LANGUAGE_MODEL: "LANGUAGE_MODEL_FREE_FORM",
          EXTRA_MAX_RESULTS: 5,
          EXTRA_PARTIAL_RESULTS: true,
          REQUEST_PERMISSIONS_AUTO: true,
          ...options
        };
        await Voice.startSpeech(locale, speechOptions);
      default:
        throw new Exception("Error: Platform not supported");
    }
  }

  async stop() {
    if (!this._loaded && !this._listeners) {
      return;
    }
    // on Android this may throw an error
    await Voice.stopSpeech();
  }

  async cancel() {
    if (!this._loaded && !this._listeners) {
      return;
    }
    // on Android this may throw an error
    await Voice.cancelSpeech();
  }

  async isAvailable() {
    return await Voice.isSpeechAvailable();
  }

  async isReady() {
    if (Platform.OS !== "ios") {
      return true;
    }
    return await Voice.isReady();
  }

  setCategory(category) {
    if (Platform.OS !== "ios") return;
    Voice.setCategory(category);
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
