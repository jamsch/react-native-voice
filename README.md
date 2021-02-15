![CircleCI branch][circle-ci-badge]
[![npm][npm]][npm-url]

<h1 align="center">React Native Voice</h1>
<p align="center">A speech-to-text library for <a href="https://reactnative.dev/">React Native.</a></p>

<a href="https://discord.gg/CJHKVeW6sp">
<img src="https://img.shields.io/discord/764994995098615828?label=Discord&logo=Discord&style=for-the-badge"
            alt="chat on Discord"></a>

```sh
yarn add @react-native-community/voice

# or

npm i @react-native-community/voice --save
```

Link the iOS package

```sh
npx pod-install
```

## Table of contents

- [Table of contents](#table-of-contents)
- [Linking](#linking)
  - [Manually Link Android](#manually-link-android)
  - [Manually Link iOS](#manually-link-ios)
  - [Example](#example)
  - [Android](#android)
  - [iOS](#ios)
  - [Handling errors](#handling-errors)

## Linking

Manually or automatically link the NativeModule

```sh
react-native link @react-native-community/voice
```

### Manually Link Android

- In `android/setting.gradle`

```gradle
...
include ':@react-native-community_voice', ':app'
project(':@react-native-community_voice').projectDir = new File(rootProject.projectDir, '../node_modules/@react-native-community/voice/android')
```

- In `android/app/build.gradle`

```gradle
...
dependencies {
    ...
    compile project(':@react-native-community_voice')
}
```

- In `MainApplication.java`

```java
import android.app.Application;
import com.facebook.react.ReactApplication;
import com.facebook.react.ReactPackage;
...
import com.wenkesj.voice.VoicePackage; // <------ Add this!
...

public class MainActivity extends Activity implements ReactApplication {
...
    @Override
    protected List<ReactPackage> getPackages() {
      return Arrays.<ReactPackage>asList(
        new MainReactPackage(),
        new VoicePackage() // <------ Add this!
        );
    }
}
```

### Manually Link iOS

- Drag the Voice.xcodeproj from the @react-native-community/voice/ios folder to the Libraries group on Xcode in your poject. [Manual linking](https://reactnative.dev/docs/linking-libraries-ios.html)

- Click on your main project file (the one that represents the .xcodeproj) select Build Phases and drag the static library, lib.Voice.a, from the Libraries/Voice.xcodeproj/Products folder to Link Binary With Libraries

<h2 align="center">Usage</h2>

<p align="center"><a href="https://github.com/react-native-community/voice/tree/master/example/src/VoiceTest.js">Full example for Android and iOS.</a></p>

### Example

```javascript
import Voice from '@react-native-community/voice';
import React, {Component} from 'react';

class VoiceTest extends Component {
  constructor(props) {
    Voice.onSpeechStart = this.onSpeechStartHandler.bind(this);
    Voice.onSpeechEnd = this.onSpeechEndHandler.bind(this);
    Voice.onSpeechPartialResults = this.onSpeechPartialResultsHandler.bind(this);
    Voice.onSpeechResults = this.onSpeechResultsHandler.bind(this);
    Voice.onSpeechError = this.onSpeechErrorHandler.bind(this);
  }

  componentWillUnmount() {
    // Remove all listeners
    Voice.removeAllListeners();
  }

  onSpeechStartHandler() {
    console.log("Speech started");
    // Update state to notify user that speech recognition has started
  }

   onSpeechPartialResultsHandler(e) {
    // e = { value: string[] }
    // Loop through e.value for speech transcription results
    console.log("Partial results", e);
  }

  onSpeechResultsHandler(e) {
    // e = { value: string[] }
    // Loop through e.value for speech transcription results
    console.log("Speech results", e);
  }

  onSpeechEndHandler(e) {
    // e = { error?: boolean }
    console.log("Speech ended", e);
  }

  onSpeechErrorHandler(e) {
    // e = { code?: string, message?: string }
    switch (e.code) { ... }
  }

  onStartButtonPress = async () => {
    try {
      await Voice.start("en_US");
    } catch (exception) {
      // exception = Error | { code: string, message?: string }
      onSpeechErrorHandler(exception);
    }
  };

  render() {
    return (
      <TouchableOpacity onPress={this.onStartButtonPress}>
        <View>
          <Text>Start</Text>
        </View>
      </TouchableOpacity>
    );
  }
}
```

<h2 align="center">API</h2>

<p align="center">Static access to the Voice API.</p>

**All methods _now_ return a `new Promise` for `async/await` compatibility.**

| Method Name                          | Description                                                                                                                                                             | Platform     |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| Voice.isAvailable()                  | Checks whether a speech recognition service is available on the system.                                                                                                 | Android, iOS |
| Voice.start(locale)                  | Starts listening for speech for a specific locale. Returns null if no error occurs.                                                                                     | Android, iOS |
| Voice.stop()                         | Stops listening for speech. Returns null if no error occurs.                                                                                                            | Android, iOS |
| Voice.cancel()                       | Cancels the speech recognition. Returns null if no error occurs.                                                                                                        | Android, iOS |
| Voice.destroy()                      | Destroys the current SpeechRecognizer instance. Returns null if no error occurs.                                                                                        | Android, iOS |
| Voice.removeAllListeners()           | Cleans/nullifies overridden `Voice` static methods.                                                                                                                     | Android, iOS |
| Voice.isRecognizing()                | Return if the SpeechRecognizer is recognizing.                                                                                                                          | Android, iOS |
| Voice.getSpeechRecognitionServices() | Returns a list of the speech recognition engines available on the device. (Example: `['com.google.android.googlequicksearchbox']` if Google is the only one available.) | Android      |

<h2 align="center">Events</h2>

<p align="center">Callbacks that are invoked when a native event emitted.</p>

| Event Name                          | Description                                            | Event                                           | Platform     |
| ----------------------------------- | ------------------------------------------------------ | ----------------------------------------------- | ------------ |
| Voice.onSpeechStart(event)          | Invoked when `.start()` is called without error.       | `{ error: false }`                              | Android, iOS |
| Voice.onSpeechRecognized(event)     | Invoked when speech is recognized.                     | `{ error: false }`                              | Android, iOS |
| Voice.onSpeechEnd(event)            | Invoked when SpeechRecognizer stops recognition.       | `{ error: false }`                              | Android, iOS |
| Voice.onSpeechError(event)          | Invoked when an error occurs.                          | `{ error: Description of error as string }`     | Android, iOS |
| Voice.onSpeechResults(event)        | Invoked when SpeechRecognizer is finished recognizing. | `{ value: [..., 'Speech recognized'] }`         | Android, iOS |
| Voice.onSpeechPartialResults(event) | Invoked when any results are computed.                 | `{ value: [..., 'Partial speech recognized'] }` | Android, iOS |
| Voice.onSpeechVolumeChanged(event)  | Invoked when pitch that is recognized changed.         | `{ value: pitch in dB }`                        | Android      |

<h2 align="center">Permissions</h2>

<p align="center">Arguably the most important part.</p>

### Android

While the included `VoiceTest` app works without explicit permissions checks and requests, it may be necessary to add a permission request for `RECORD_AUDIO` for some configurations.
Since Android M (6.0), [user need to grant permission at runtime (and not during app installation)](https://developer.android.com/training/permissions/requesting.html).
By default, calling the `startSpeech` method will invoke `RECORD AUDIO` permission popup to the user. This can be disabled by passing `REQUEST_PERMISSIONS_AUTO: true` in the options argument.

If you're running an ejected expo/expokit app, you may run into issues with permissions on Android and get the following error `host.exp.exponent.MainActivity cannot be cast to com.facebook.react.ReactActivity startSpeech`. This can be resolved by prompting for permssion using the `expo-permission` package before starting recognition.

```js
import { Permissions } from "expo";
async componentDidMount() {
	const { status, expires, permissions } = await Permissions.askAsync(
		Permissions.AUDIO_RECORDING
	);
	if (status !== "granted") {
		//Permissions not granted. Don't show the start recording button because it will cause problems if it's pressed.
		this.setState({showRecordButton: false});
	} else {
		this.setState({showRecordButton: true});
	}
}
```

**Notes on Android**

Even after all the permissions are correct in Android, there is one last thing to make sure this libray is working fine on Android. Please make sure the device has Google Speech Recognizing Engine such as `com.google.android.googlequicksearchbox` by calling `Voice.getSpeechRecognitionServices()`. Since Android phones can be configured with so many options, even if a device has googlequicksearchbox engine, it could be configured to use other services. You can check which serivce is used for Voice Assistive App in following steps for most Android phones:

`Settings > App Management > Default App > Assistive App and Voice Input > Assistive App`

Above flow can vary depending on the Android models and manufactures. For Huawei phones, there might be a chance that the device cannot install Google Services.

**How can I get `com.google.android.googlequicksearchbox` in the device?**

Please ask users to install [Google Search App](https://play.google.com/store/apps/details?id=com.google.android.googlequicksearchbox&hl=en).

### iOS

Need to include permissions for `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` inside Info.plist for iOS. See the included `VoiceTest` for how to handle these cases.

```xml
<dict>
  ...
  <key>NSMicrophoneUsageDescription</key>
  <string>Description of why you require the use of the microphone</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Description of why you require the use of the speech recognition</string>
  ...
</dict>
```

Please see the documentation provided by ReactNative for this: [PermissionsAndroid](https://reactnative.dev/docs/permissionsandroid.html)

[npm]: https://img.shields.io/npm/v/@react-native-community/voice.svg?style=flat-square
[npm-url]: https://npmjs.com/package/@react-native-community/voice
[circle-ci-badge]: https://img.shields.io/circleci/project/github/react-native-community/voice/master.svg?style=flat-square

### Handling errors

This applies to `Voice.onSpeechError(e)` and when `await Voice.start()` throws an exception.

```javascript
try {
  await Voice.start();
} catch (e) {
  // Note: on Android this will *likely* return an Error object.
  // e: Error | { code: string, message?: string }
  // switch (e.code) { ... }
}
```

| Code               | Description                                                     | Platform     |
| ------------------ | --------------------------------------------------------------- | ------------ |
| `permissions`      | User denied microphone/speech recognition permissions           | Android, iOS |
| `recognizer_busy`  | Speech recognition has already started                          | Android, iOS |
| `not_available`    | Speech recognition is not available on the device               | Android, iOS |
| `audio`            | Audio engine / Audio session error                              | Android, iOS |
| `network`          | Network error                                                   | Android      |
| `network_timeout`  | Network timeout error                                           | Android      |
| `speech_timeout`   | Speech recognition timeout                                      | Android      |
| `no_match`         | No recognition matches                                          | Android      |
| `server`           | Server error                                                    | Android      |
| `restricted`       | Speech recognition is restricted                                | iOS          |
| `not_authorized`   | Speech recognition is not authorized                            | iOS          |
| `not_ready`        | Speech recognition is not ready to start                        | iOS          |
| `recognition_init` | Speech recognition initialization failed                        | iOS          |
| `start_recording`  | `[inputNode installTapOnBus:0...]` call failed                  | iOS          |
| `input`            | Audio engine has no input node                                  | iOS          |
| `recognition_fail` | General failure while using recognition. Has a `"message"` prop | iOS          |

<h2 align="center">Contributors</h2>

- @asafron
- @BrendanFDMoore
- @brudny
- @chitezh
- @ifsnow
- @jamsch
- @misino
- @Noitidart
- @ohtangza & @hayanmind
- @rudiedev6
- @tdonia
- @wenkesj
