import { EventSubscriptionVendor } from 'react-native';

export type VoiceModule = {
  /**
   * Gets list of SpeechRecognitionServices used.
   * @platform android
   */
  getSpeechRecognitionServices(): Promise<string[]> | void;
  destroySpeech(): Promise<void>;
  startSpeech(locale?: string, extraOptions?: any): Promise<void>;
  stopSpeech(): Promise<void>;
  cancelSpeech(): Promise<void>;
  isRecognizing(): Promise<boolean>;
  isSpeechAvailable(): Promise<boolean>;
} & SpeechEvents &
  EventSubscriptionVendor;

export type SpeechEvents = {
  onSpeechStart?: (e: SpeechStartEvent) => void;
  onSpeechRecognized?: (e: SpeechRecognizedEvent) => void;
  onSpeechEnd?: (e: SpeechEndEvent) => void;
  onSpeechError?: (e: SpeechErrorEvent) => void;
  onSpeechResults?: (e: SpeechResultsEvent) => void;
  onSpeechPartialResults?: (e: SpeechResultsEvent) => void;
  onSpeechVolumeChanged?: (e: SpeechVolumeChangeEvent) => void;
};

export type SpeechStartEvent = {
  error?: boolean;
};

export type SpeechRecognizedEvent = {
  isFinal?: boolean;
};

export type SpeechResultsEvent = {
  value?: string[];
};

export type SpeechErrorEvent = {
  code?: // Android & IOS
  | 'speech_timeout'
    | 'permissions'
    | 'recognizer_buzy'
    | 'input'
    // Android
    | 'not_available'
    | 'network'
    | 'network_timeout'
    | 'speech_input'
    | 'audio'
    // iOS only
    | 'restricted'
    | 'not_authorized'
    | 'not_ready'
    | 'no_match'
    | 'recognition_init'
    | 'recognition_fail'
    | 'start_recording';
  message?: string;
};

export type SpeechEndEvent = {
  error?: boolean;
};

export type SpeechVolumeChangeEvent = {
  value?: number;
};
