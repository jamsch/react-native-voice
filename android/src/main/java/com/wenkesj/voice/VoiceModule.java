package com.wenkesj.voice;

import android.Manifest;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.support.annotation.NonNull;
import android.util.Log;

import com.facebook.react.ReactActivity;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.ReadableMapKeySetIterator;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import com.facebook.react.modules.core.PermissionListener;

import java.util.ArrayList;
import java.util.Locale;

import javax.annotation.Nullable;

public class VoiceModule extends ReactContextBaseJavaModule implements RecognitionListener {

  final ReactApplicationContext reactContext;
  private SpeechRecognizer speech = null;
  private boolean isRecognizing = false;
  private String locale = null;

  public VoiceModule(ReactApplicationContext reactContext) {
    super(reactContext);
    this.reactContext = reactContext;
  }

  private String getLocale(String locale) {
    if (locale != null && !locale.equals("")) {
      return locale;
    }

    return Locale.getDefault().toString();
  }

  private void startListening(ReadableMap opts) {
    if (speech != null) {
      speech.destroy();
      speech = null;
    }
    speech = SpeechRecognizer.createSpeechRecognizer(this.reactContext, ComponentName.unflattenFromString("com.google.android.googlequicksearchbox/com.google.android.voicesearch.serviceapi.GoogleRecognitionService"));
    speech.setRecognitionListener(this);

    final Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);

    // Load the intent with options from JS
    ReadableMapKeySetIterator iterator = opts.keySetIterator();
    while (iterator.hasNextKey()) {
      String key = iterator.nextKey();
      switch (key) {
        case "EXTRA_LANGUAGE_MODEL":
          switch (opts.getString(key)) {
            case "LANGUAGE_MODEL_FREE_FORM":
              intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
              break;
            case "LANGUAGE_MODEL_WEB_SEARCH":
              intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH);
              break;
            default:
              intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
              break;
          }
          break;
        case "EXTRA_MAX_RESULTS": {
          Double extras = opts.getDouble(key);
          intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, extras.intValue());
          break;
        }
        case "EXTRA_PARTIAL_RESULTS": {
          intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, opts.getBoolean(key));
          break;
        }
        case "EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS": {
          Double extras = opts.getDouble(key);
          intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, extras.intValue());
          break;
        }
        case "EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS": {
          Double extras = opts.getDouble(key);
          intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, extras.intValue());
          break;
        }
        case "EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS": {
          Double extras = opts.getDouble(key);
          intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, extras.intValue());
          break;
        }
      }
    }

    intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, getLocale(this.locale));
    speech.startListening(intent);
  }

  @Override
  public String getName() {
    return "RCTVoice";
  }

  @ReactMethod
  public void startSpeech(final String locale, final ReadableMap opts, final Promise promise) {
    if (!isPermissionGranted() && opts.getBoolean("REQUEST_PERMISSIONS_AUTO")) {
      String[] PERMISSIONS = {Manifest.permission.RECORD_AUDIO};
      if (this.getCurrentActivity() != null) {
        ((ReactActivity) this.getCurrentActivity()).requestPermissions(PERMISSIONS, 1, new PermissionListener() {
          public boolean onRequestPermissionsResult(final int requestCode,
                                                    @NonNull final String[] permissions,
                                                    @NonNull final int[] grantResults) {
            boolean permissionsGranted = true;
            for (int i = 0; i < permissions.length; i++) {
              final boolean granted = grantResults[i] == PackageManager.PERMISSION_GRANTED;
              permissionsGranted = permissionsGranted && granted;
            }

            return permissionsGranted;
          }
        });
      }
      return;
    }

    this.locale = locale;

    Handler mainHandler = new Handler(this.reactContext.getMainLooper());
    mainHandler.post(new Runnable() {
      @Override
      public void run() {
        try {
          startListening(opts);
          isRecognizing = true;
          promise.resolve(false);
        } catch (Exception e) {
          promise.reject(e.getMessage());
        }
      }
    });
  }

  @ReactMethod
  public void stopSpeech(final Promise promise) {
    Handler mainHandler = new Handler(this.reactContext.getMainLooper());
    mainHandler.post(new Runnable() {
      @Override
      public void run() {
        try {
          speech.stopListening();
          isRecognizing = false;
          promise.resolve(false);
        } catch(Exception e) {
          promise.reject(e.getMessage());
        }
      }
    });
  }

  @ReactMethod
  public void cancelSpeech(final Promise promise) {
    Handler mainHandler = new Handler(this.reactContext.getMainLooper());
    mainHandler.post(new Runnable() {
      @Override
      public void run() {
        try {
          speech.cancel();
          isRecognizing = false;
          promise.resolve(false);
        } catch (Exception e) {
          promise.reject(e.getMessage());
        }
      }
    });
  }

  @ReactMethod
  public void destroySpeech(final Promise promise) {
    Handler mainHandler = new Handler(this.reactContext.getMainLooper());
    mainHandler.post(new Runnable() {
      @Override
      public void run() {
        try {
          speech.destroy();
          speech = null;
          isRecognizing = false;
          promise.resolve(false);
        } catch(Exception e) {
          promise.reject(e.getMessage());
        }
      }
    });
  }

  @ReactMethod
  public void isSpeechAvailable(final Promise promise) {
    final VoiceModule self = this;
    Handler mainHandler = new Handler(this.reactContext.getMainLooper());
    mainHandler.post(new Runnable() {
      @Override
      public void run() {
        try {
          Boolean isSpeechAvailable = SpeechRecognizer.isRecognitionAvailable(self.reactContext);
          promise.resolve(isSpeechAvailable);
        } catch(Exception e) {
          promise.resolve(false);
        }
      }
    });
  }

  private boolean isPermissionGranted() {
    String permission = Manifest.permission.RECORD_AUDIO;
    int res = getReactApplicationContext().checkCallingOrSelfPermission(permission);
    return res == PackageManager.PERMISSION_GRANTED;
  }

  @ReactMethod
  public void isRecognizing(Promise promise) {
    promise.resolve(isRecognizing);
  }

  private void sendEvent(String eventName, @Nullable WritableMap params) {
    this.reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
      .emit(eventName, params);
  }

  @Override
  public void onBeginningOfSpeech() {
    sendEvent("onSpeechStart", null);
    Log.d("ASR", "onBeginningOfSpeech()");
  }

  @Override
  public void onBufferReceived(byte[] buffer) {
    sendEvent("onSpeechRecognized", null);
    Log.d("ASR", "onBufferReceived()");
  }

  @Override
  public void onEndOfSpeech() {
    sendEvent("onSpeechEnd", null);
    Log.d("ASR", "onEndOfSpeech()");
    isRecognizing = false;
  }

  @Override
  public void onError(int errorCode) {
    String errorCodeText = getErrorText(errorCode);
    WritableMap event = Arguments.createMap();
    event.putString("code", errorCodeText);
    sendEvent("onSpeechError", event);
    Log.d("ASR", "onError() - " + errorCodeText);
  }

  @Override
  public void onEvent(int arg0, Bundle arg1) { }

  @Override
  public void onPartialResults(Bundle results) {
    WritableArray arr = Arguments.createArray();

    ArrayList<String> matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
    for (String result : matches) {
      arr.pushString(result);
    }

    WritableMap event = Arguments.createMap();
    event.putArray("value", arr);
    sendEvent("onSpeechPartialResults", event);
    Log.d("ASR", "onPartialResults()");
  }

  @Override
  public void onReadyForSpeech(Bundle arg0) {
    sendEvent("onSpeechStart", null);
    Log.d("ASR", "onReadyForSpeech()");
  }

  @Override
  public void onResults(Bundle results) {
    WritableArray arr = Arguments.createArray();

    ArrayList<String> matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
    for (String result : matches) {
      arr.pushString(result);
    }

    WritableMap event = Arguments.createMap();
    event.putArray("value", arr);
    sendEvent("onSpeechResults", event);
    Log.d("ASR", "onResults()");
  }

  @Override
  public void onRmsChanged(float rmsdB) {
    WritableMap event = Arguments.createMap();
    event.putDouble("value", (double) rmsdB);
    sendEvent("onSpeechVolumeChanged", event);
  }

  public static String getErrorText(int errorCode) {
    String message;
    switch (errorCode) {
      case SpeechRecognizer.ERROR_AUDIO:
        message = "audio";
        break;
      case SpeechRecognizer.ERROR_CLIENT:
        message = "client";
        break;
      case SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS:
        message = "permissions";
        break;
      case SpeechRecognizer.ERROR_NETWORK:
        message = "network";
        break;
      case SpeechRecognizer.ERROR_NETWORK_TIMEOUT:
        message = "network_timeout";
        break;
      case SpeechRecognizer.ERROR_NO_MATCH:
        message = "no_match";
        break;
      case SpeechRecognizer.ERROR_RECOGNIZER_BUSY:
        message = "recognizer_busy";
        break;
      case SpeechRecognizer.ERROR_SERVER:
        message = "server";
        break;
      case SpeechRecognizer.ERROR_SPEECH_TIMEOUT:
        message = "speech_timeout";
        break;
      default:
        message = "unknown";
        break;
    }
    return message;
  }
}

