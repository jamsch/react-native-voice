#import "Voice.h"
#import <React/RCTLog.h>
#import <UIKit/UIKit.h>
#import <React/RCTUtils.h>
#import <React/RCTEventEmitter.h>
#import <Speech/Speech.h>

@interface Voice () <SFSpeechRecognizerDelegate>
/** Whether speech recognition is finishing.. */
@property (nonatomic) BOOL isTearingDown;
@property (nonatomic) SFSpeechRecognizer* speechRecognizer;
@property (nonatomic) SFSpeechAudioBufferRecognitionRequest* recognitionRequest;
@property (nonatomic) AVAudioEngine* audioEngine;
@property (nonatomic) SFSpeechRecognitionTask* recognitionTask;
@property (nonatomic) AVAudioSession* audioSession;
@property (nonatomic) NSString *sessionId;
/** Previous category the user was on prior to starting speech recognition */
@property (nonatomic) NSString* priorAudioCategory;

@end

@implementation Voice
{
}

- (BOOL)isHeadsetPluggedIn {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

-(BOOL)isHeadSetBluetooth {
    NSArray *arrayInputs = [[AVAudioSession sharedInstance] availableInputs];
    for (AVAudioSessionPortDescription *port in arrayInputs)
    {
        if ([port.portType isEqualToString:AVAudioSessionPortBluetoothHFP])
        {
            return YES;
        }
    }
    return NO;
}

/** Returns "YES" if no errors had occurred */
-(BOOL) setupAudioSession {
    if ([self isHeadsetPluggedIn] || [self isHeadSetBluetooth]){
        [self.audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error: nil];
    }
    else {
        [self.audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error: nil];
    }
    
    NSError* audioSessionError = nil;
    
    // Activate the audio session
    [self.audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&audioSessionError];
    
    if (audioSessionError != nil) {
        [self sendResult:@{@"code": @"audio", @"message": [audioSessionError localizedDescription]} :nil :nil :nil];
        return NO;
    }
    
    return YES;
}

-(void) resetAudioSession {
    if (self.audioSession == nil) {
        self.audioSession = [AVAudioSession sharedInstance];
    }
    NSString* audioCategory = [self.audioSession category];
    // Category hasn't changed -- do nothing
    // if ([self.priorAudioCategory isEqualToString:audioCategory]) return;
    // Current audio category doesn't contain "Record" -- do nothing
    if ([self.priorAudioCategory rangeOfString:@"Record"].location == NSNotFound) {
        return;
    } else {
        // Prior category is either "PlayAndRecord" or "Record". Revert to "Ambient" as default
        self.priorAudioCategory = AVAudioSessionCategoryAmbient;
    };
    
    // Reset back to the previous category
    if ([self isHeadsetPluggedIn] || [self isHeadSetBluetooth]) {
        [self.audioSession setCategory:self.priorAudioCategory withOptions:AVAudioSessionCategoryOptionAllowBluetooth error: nil];
    } else {
        [self.audioSession setCategory:self.priorAudioCategory withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error: nil];
    }
    // Set audio session to inactive and notify other sessions
    // [self.audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error: nil];
    // Remove pointer reference
    self.audioSession = nil;
    // Reset session
    self.sessionId = nil;
}

- (void) setupAndStartRecognizing:(NSString*)localeStr {
    self.audioSession = [AVAudioSession sharedInstance];
    self.priorAudioCategory = [self.audioSession category];
    self.sessionId = [[NSUUID UUID] UUIDString];
    
    // Tear down resources before starting speech recognition..
    [self teardown];
    
    NSLocale* locale = nil;
    if ([localeStr length] > 0) {
        locale = [NSLocale localeWithLocaleIdentifier:localeStr];
    }
    
    if (locale) {
        self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    } else {
        self.speechRecognizer = [[SFSpeechRecognizer alloc] init];
    }
    
    self.speechRecognizer.delegate = self;
    
    // Start audio session...
    if (![self setupAudioSession]) {
        [self teardown];
        return;
    }
    
    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    // Configure request so that results are returned before audio recording is finished
    self.recognitionRequest.shouldReportPartialResults = YES;
    
    if (self.recognitionRequest == nil) {
        [self sendResult:@{@"code": @"recognition_init"} :nil :nil :nil];
        return;
    }
    
    if (self.audioEngine == nil) {
        self.audioEngine = [[AVAudioEngine alloc] init];
    }
    
    AVAudioInputNode* inputNode = self.audioEngine.inputNode;
    if (inputNode == nil) {
        [self sendResult:@{@"code": @"input"} :nil :nil :nil];
        return;
    }
    
    [self sendEventWithName:@"onSpeechStart" body:nil];
    
    
    // A recognition task represents a speech recognition session.
    // We keep a reference to the task so that it can be cancelled.
    NSString *taskSessionId = self.sessionId;
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        if (![taskSessionId isEqualToString:self.sessionId]) {
            // session ID has changed, so ignore any capture results and error
            return;
        }
        if (error != nil) {
            NSString *errorMessage = [NSString stringWithFormat:@"%ld/%@", error.code, [error localizedDescription]];
            [self sendResult:@{@"code": @"recognition_fail", @"message": errorMessage} :nil :nil :nil];
            [self teardown];
            return;
        }
        
        BOOL isFinal = result.isFinal;
        if (result != nil) {
            NSMutableArray* transcriptionDics = [NSMutableArray new];
            for (SFTranscription* transcription in result.transcriptions) {
                [transcriptionDics addObject:transcription.formattedString];
            }
            
            [self sendResult :nil :result.bestTranscription.formattedString :transcriptionDics :[NSNumber numberWithBool:isFinal]];
        }
        
        if (isFinal) {
            if (self.recognitionTask.isCancelled || self.recognitionTask.isFinishing) {
                [self sendEventWithName:@"onSpeechEnd" body:nil];
            }
            [self teardown];
        }
    }];
    
    AVAudioFormat* recordingFormat = [inputNode outputFormatForBus:0];
    AVAudioMixerNode *mixer = [[AVAudioMixerNode alloc] init];
    [self.audioEngine attachNode:mixer];
    
    // Start recording and append recording buffer to speech recognizer
    @try {
        [mixer installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
            // Todo: write recording buffer to file (if user opts in)
            if (self.recognitionRequest != nil) {
                [self.recognitionRequest appendAudioPCMBuffer:buffer];
            }
        }];
    } @catch (NSException *exception) {
        [self sendResult:@{@"code": @"start_recording", @"message": [exception reason]} :nil :nil :nil];
        [self teardown];
        return;
    } @finally {}
    
    [self.audioEngine connect:inputNode to:mixer format:recordingFormat];
    [self.audioEngine prepare];
    NSError* audioSessionError = nil;
    [self.audioEngine startAndReturnError:&audioSessionError];
    if (audioSessionError != nil) {
        [self sendResult:@{@"code": @"audio", @"message": [audioSessionError localizedDescription]} :nil :nil :nil];
        [self teardown];
        return;
    }
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[
             @"onSpeechResults",
             @"onSpeechStart",
             @"onSpeechPartialResults",
             @"onSpeechError",
             @"onSpeechEnd",
             @"onSpeechRecognized",
             @"onSpeechVolumeChanged"
             ];
}

- (void) sendResult:(NSDictionary*)error :(NSString*)bestTranscription :(NSArray*)transcriptions :(NSNumber*)isFinal {
    if (error != nil) {
        [self sendEventWithName:@"onSpeechError" body:error];
    }
    if (bestTranscription != nil) {
        if ([isFinal boolValue] == YES) {
            [self sendEventWithName:@"onSpeechResults" body:@{@"value":@[bestTranscription]} ];
        } else {
            [self sendEventWithName:@"onSpeechPartialResults" body:@{@"value":transcriptions} ];
        }
    } else if (transcriptions != nil) {
        [self sendEventWithName:@"onSpeechPartialResults" body:@{@"value":transcriptions} ];
    }
    
    if ([isFinal boolValue] == YES) {
        [self sendEventWithName:@"onSpeechRecognized" body: @{@"isFinal": isFinal}];
    }
}

- (void) teardown {
    self.isTearingDown = YES;
    [self.recognitionTask cancel];
    self.recognitionTask = nil;
    
    // Set back audio session category
    [self resetAudioSession];
    
    // End recognition request
    [self.recognitionRequest endAudio];
    
    // Remove tap on bus
    [self.audioEngine.inputNode removeTapOnBus:0];
    [self.audioEngine.inputNode reset];
    
    // Stop audio engine and dereference it for re-allocation
    if (self.audioEngine.isRunning) {
        [self.audioEngine stop];
        [self.audioEngine reset];
        self.audioEngine = nil;
    }
    
    self.recognitionRequest = nil;
    self.isTearingDown = NO;
}

// Called when the availability of the given recognizer changes
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    if (available == false) {
        [self sendResult:@{@"code": @"not_available"} :nil :nil :nil];
    }
}

RCT_EXPORT_METHOD(stopSpeech:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    [self.recognitionTask finish];
    resolve(nil);
}


RCT_EXPORT_METHOD(cancelSpeech:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [self.recognitionTask cancel];
    resolve(nil);
}

RCT_EXPORT_METHOD(destroySpeech:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [self teardown];
    resolve(nil);
}

RCT_EXPORT_METHOD(isSpeechAvailable:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                resolve(@true);
                break;
            default:
                resolve(@false);
        }
    }];
}

RCT_EXPORT_METHOD(isRecognizing:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    if (self.recognitionTask != nil) {
        switch (self.recognitionTask.state) {
            case SFSpeechRecognitionTaskStateRunning:
                resolve(@true);
                return;
            default:
                resolve(@false);
                return;
        }
    }
    resolve(@false);
}

RCT_EXPORT_METHOD(isReady:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    if (self.isTearingDown || self.recognitionTask != nil) {
        resolve(@false);
        return;
    }
    resolve(@true);
}

RCT_EXPORT_METHOD(startSpeech:(NSString*)localeStr
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.sessionId != nil) {
        reject(@"recognizer_busy", @"Speech recognition already started!", nil);
        return;
    }
    
    if (self.isTearingDown) {
        reject(@"not_ready", @"Speech recognition is not ready", nil);
        return;
    };
    
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                reject(@"not_authorized", @"Speech recognition is not authorized", nil);
                return;
            case SFSpeechRecognizerAuthorizationStatusDenied:
                reject(@"permissions", @"User denied permission to use speech recognition", nil);
                return;
            case SFSpeechRecognizerAuthorizationStatusRestricted:
                reject(@"restricted", @"Speech recognition restricted on this device", nil);
                return;
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                [self setupAndStartRecognizing:localeStr];
                resolve(nil);
                return;
        }
    }];
}

// Used to control the audio category in case the user loads audio
// through a different audio library while speech recognition may be initializing
// Credits: react-native-sound
RCT_EXPORT_METHOD(setCategory:(NSString *)categoryName
                  mixWithOthers:(BOOL)mixWithOthers) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *category = nil;
    
    if ([categoryName isEqual: @"Ambient"]) {
        category = AVAudioSessionCategoryAmbient;
    } else if ([categoryName isEqual: @"SoloAmbient"]) {
        category = AVAudioSessionCategorySoloAmbient;
    } else if ([categoryName isEqual: @"Playback"]) {
        category = AVAudioSessionCategoryPlayback;
    } else if ([categoryName isEqual: @"Record"]) {
        category = AVAudioSessionCategoryRecord;
    } else if ([categoryName isEqual: @"PlayAndRecord"]) {
        category = AVAudioSessionCategoryPlayAndRecord;
    }
#if TARGET_OS_IOS
    else if ([categoryName isEqual: @"AudioProcessing"]) {
        category = AVAudioSessionCategoryAudioProcessing;
    }
#endif
    else if ([categoryName isEqual: @"MultiRoute"]) {
        category = AVAudioSessionCategoryMultiRoute;
    }
    
    if (category) {
        if (mixWithOthers) {
            [session setCategory: category withOptions:AVAudioSessionCategoryOptionMixWithOthers error: nil];
        } else {
            [session setCategory: category error: nil];
        }
    }
}

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()



@end
