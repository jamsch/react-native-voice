package com.wenkesj.voice;

import android.Manifest;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Bundle;
import android.os.Handler;
import android.speech.RecognitionListener;
import android.speech.RecognitionService;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import androidx.annotation.NonNull;
import android.util.Log;

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
import com.facebook.react.modules.core.PermissionAwareActivity;
import com.facebook.react.modules.core.PermissionListener;

import java.util.ArrayList;
import java.util.List;
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
    
    if (opts.hasKey("RECOGNIZER_ENGINE")) {
      switch (opts.getString("RECOGNIZER_ENGINE")) {
        case "GOOGLE": {
          speech = SpeechRecognizer.createSpeechRecognizer(this.reactContext, ComponentName.unflattenFromString("com.google.android.googlequicksearchbox/com.google.android.voicesearch.serviceapi.GoogleRecognitionService"));
          break;
        }
        default:
          speech = SpeechRecognizer.createSpeechRecognizer(this.reactContext);
      }
    } else {
      speech = SpeechRecognizer.createSpeechRecognizer(this.reactContext);
    }

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

  private void startSpeechWithPermissions(final String locale, final ReadableMap opts, final Promise promise) {
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

  @Override
  public String getName() {
    return "RCTVoice";
  }

  private final int RECORD_AUDIO_PERMISSIONS = 1;

  @ReactMethod
  public void startSpeech(final String locale, final ReadableMap opts, final Promise promise) {
    // Check whether speech recognition is available
    if (!hasSpeechServices()) {
       promise.reject("not_available", "Speech Recognition is not available on this device");
       return;
    }

    if (isPermissionGranted()) {
      startSpeechWithPermissions(locale, opts, promise);
      return;
    }
    // User opted out of asking for permissions (or activity is falsy)
    if (!opts.getBoolean("REQUEST_PERMISSIONS_AUTO") || this.getCurrentActivity() == null) {
      promise.reject("permissions", "User needs to accept record audio permissions");
      return;
    }

    String[] PERMISSIONS = {Manifest.permission.RECORD_AUDIO};

    ((PermissionAwareActivity) this.getCurrentActivity()).requestPermissions(PERMISSIONS, RECORD_AUDIO_PERMISSIONS, new PermissionListener() {
      public boolean onRequestPermissionsResult(final int requestCode,
                                                @NonNull final String[] permissions,
                                                @NonNull final int[] grantResults) {
        switch (requestCode) {
          case RECORD_AUDIO_PERMISSIONS: {
            Boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            if (granted) {
                startSpeechWithPermissions(locale, opts, promise);
            } else {
              promise.reject("permissions", "User needs to accept record audio permissions");
            }
            return granted;
          }
          default:
            return false;
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
          if (speech != null) {
            speech.stopListening();
          }
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
          if (speech != null) {
            speech.cancel();
          }
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
          if (speech != null) {
            speech.destroy();
          }
          speech = null;
          isRecognizing = false;
          promise.resolve(false);
        } catch(Exception e) {
          promise.reject(e.getMessage());
        }
      }
    });
  }

  private Boolean hasSpeechServices() {
    try {
      Boolean isSpeechAvailable = SpeechRecognizer.isRecognitionAvailable(this.reactContext);
      if (!isSpeechAvailable) {
        return false;
      }
      // Some devices seem to report "true" on "isRecognitionAvailable" while having no intent services.
      final List<ResolveInfo> services = this.reactContext.getPackageManager()
        .queryIntentServices(new Intent(RecognitionService.SERVICE_INTERFACE), 0);
      return (services.size() > 0);
    } catch(Exception e) {
      return false;
    }
  }

  @ReactMethod
  public void isSpeechAvailable(final Promise promise) {
    final VoiceModule self = this;
    Handler mainHandler = new Handler(this.reactContext.getMainLooper());
    mainHandler.post(new Runnable() {
      @Override
      public void run() {
        promise.resolve(hasSpeechServices());
      }
    });
  }

  @ReactMethod
  public void getSpeechRecognitionServices(Promise promise) {
    final List<ResolveInfo> services = this.reactContext.getPackageManager()
        .queryIntentServices(new Intent(RecognitionService.SERVICE_INTERFACE), 0);
    WritableArray serviceNames = Arguments.createArray();
    for (ResolveInfo service : services) {
      serviceNames.pushString(service.serviceInfo.packageName);
    }

    promise.resolve(serviceNames);
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

    try {
        // On some devices, this error may pop up:
        // Attempt to invoke virtual method 'java.util.Iterator java.util.ArrayList.iterator()' on a null object reference
        ArrayList<String> matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        for (String result : matches) {
          arr.pushString(result);
        }

        WritableMap event = Arguments.createMap();
        event.putArray("value", arr);
        sendEvent("onSpeechPartialResults", event);
        Log.d("ASR", "onPartialResults()");
    } catch (Exception e) {
        Log.d("ASR", "onPartialResults() - ERROR");
    }
  }

  @Override
  public void onReadyForSpeech(Bundle arg0) {
    sendEvent("onSpeechStart", null);
    Log.d("ASR", "onReadyForSpeech()");
  }

  @Override
  public void onResults(Bundle results) {
    WritableArray arr = Arguments.createArray();
    try {
        // On some devices, this error may pop up:
        // Attempt to invoke virtual method 'java.util.Iterator java.util.ArrayList.iterator()' on a null object reference
        ArrayList<String> matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        for (String result : matches) {
          arr.pushString(result);
        }

        WritableMap event = Arguments.createMap();
        event.putArray("value", arr);
        sendEvent("onSpeechResults", event);
        Log.d("ASR", "onResults()");
    } catch (Exception e) {
        Log.d("ASR", "onResults() - ERROR");
    }
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

