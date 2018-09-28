#import "Voice.h"
#import <React/RCTLog.h>
#import <UIKit/UIKit.h>
#import <React/RCTConvert.h>
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
// Recording options
@property (nonatomic) AVAudioFile *outputFile;
@property (nonatomic) BOOL recordingEnabled;
@property (nonatomic) NSString *recordingFileName;
/** Previous category the user was on prior to starting speech recognition */
@property (nonatomic) NSString *priorAudioCategory;


@end

@implementation Voice

static AVAudioNodeBus const bus = 0;
static AVAudioFrameCount const bufferSize = 1024;

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
    if (!self.audioSession) {
        self.audioSession = [AVAudioSession sharedInstance];
    }
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

-(NSURL *)applicationDocumentsDirectory {
    NSString *documentsDirectory;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if ([paths count] > 0) {
        documentsDirectory = [paths objectAtIndex:0];
    }
    // Important that we use fileURLWithPath and not URLWithString (see NSURL class reference, Apple Developer Site)
    return [NSURL fileURLWithPath:documentsDirectory];
}

-(void) resetAudioSession {
    if (!self.audioSession) {
        self.audioSession = [AVAudioSession sharedInstance];
    }
    
    // Set audio session to inactive and notify other sessions
    // [self.audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error: nil];
    NSString* audioCategory = [self.audioSession category];
    
    if (!self.priorAudioCategory) {
        self.priorAudioCategory = audioCategory;
    }
    
    // Category hasn't changed -- do nothing
    if ([self.priorAudioCategory isEqualToString:audioCategory]) return;
    // Reset back to the previous category
    if ([self isHeadsetPluggedIn] || [self isHeadSetBluetooth]) {
        [self.audioSession setCategory:self.priorAudioCategory withOptions:AVAudioSessionCategoryOptionAllowBluetooth error: nil];
    } else {
        [self.audioSession setCategory:self.priorAudioCategory withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error: nil];
    }
}

- (void) prepare:(NSString*)localeStr {
    self.audioSession = [AVAudioSession sharedInstance];
    self.priorAudioCategory = [self.audioSession category];
    // Tear down resources before starting speech recognition..
    [self stop];
    [self reset];
    
    self.sessionId = [[NSUUID UUID] UUIDString];
    
    if (!localeStr) {
        localeStr = @"en-US";
    }
    
    NSLocale* locale = [NSLocale localeWithLocaleIdentifier:localeStr];
    
    self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    [self.speechRecognizer setDelegate:self];
    
    // Start audio session...
    if (![self setupAudioSession]) {
        [self stop];
        return;
    }
    
    self.audioEngine = [[AVAudioEngine alloc] init];
}

- (void) startRecognizing {
    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    
    if (!self.recognitionRequest) {
        [self sendResult:@{@"code": @"recognition_init"} :nil :nil :nil];
        [self stop];
        return;
    }
    
    AVAudioInputNode* inputNode = self.audioEngine.inputNode;

    if (!inputNode) {
        [self sendResult:@{@"code": @"input"} :nil :nil :nil];
        [self stop];
        return;
    }
    
    AVAudioFormat* recordingFormat = [inputNode outputFormatForBus:bus];
    
    // Configure request so that results are returned before audio recording is finished
    self.recognitionRequest.shouldReportPartialResults = YES;
    
    [self sendEventWithName:@"onSpeechStart" body:nil];
    
    // A recognition task represents a speech recognition session.
    // We keep a reference to the task so that it can be cancelled.
    NSString *taskSessionId = self.sessionId;
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        // Check if Session ID has changed
        if (taskSessionId && ![taskSessionId isEqualToString:self.sessionId]) {
            [self stop];
            return;
        }

        if (error) {
            [self sendResult:@{@"code": @"recognition_fail", @"message": [error localizedDescription]} :nil :nil :nil];
            [self stop];
            [self reset];
            return;
        }
        
        BOOL isFinal = result.isFinal;
        
        if (result) {
            NSMutableArray* transcriptionDics = [NSMutableArray new];
            for (SFTranscription* transcription in result.transcriptions) {
                [transcriptionDics addObject:transcription.formattedString];
            }
            
            [self sendResult :nil :result.bestTranscription.formattedString :transcriptionDics :[NSNumber numberWithBool:isFinal]];
        }
        
        // Finish speech recognition
        if (isFinal || !self.recognitionTask || self.recognitionTask.isCancelled) {
            [self stop];
        }
    }];
    
    if (self.recordingEnabled) {
        NSURL *fileURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"output.wav"];
        // Re-allocate output file
        NSError* recordError = nil;
        self.outputFile = [[AVAudioFile alloc] initForWriting:fileURL settings:recordingFormat.settings error:&recordError];
        if (recordError) {
            [self sendResult:@{@"code": @"record_error", @"message": [recordError localizedDescription], @"domain": [recordError domain]} :nil :nil :nil];
            [self stop];
            return;
        }
    }
    
    // Start recording buffer
    @try {
        // User opted for storing recording buffer to file
        if (self.recordingEnabled && self.outputFile) {
            [inputNode installTapOnBus:bus bufferSize:bufferSize format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                @try {
                    if (self.outputFile) {
                        [self.outputFile writeFromBuffer:buffer error:nil];
                    }
                    if (self.recognitionRequest) {
                        [self.recognitionRequest appendAudioPCMBuffer:buffer];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[Error] - %@ %@", exception.name, exception.reason);
                } @finally {}
            }];
        } else {
            // Default: just append buffer to recognition request
            [inputNode installTapOnBus:bus bufferSize:bufferSize format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                // Todo: write recording buffer to file (if user opts in)
                if (self.recognitionRequest) {
                    [self.recognitionRequest appendAudioPCMBuffer:buffer];
                }
            }];
        }
    } @catch (NSException *exception) {
        NSLog(@"[Error] - %@ %@", exception.name, exception.reason);
        [self sendResult:@{@"code": @"start_recording", @"message": [exception reason]} :nil :nil :nil];
        [self stop];
        return;
    } @finally {}
    
    [self.audioEngine prepare];
    NSError* audioSessionError = nil;
    [self.audioEngine startAndReturnError:&audioSessionError];
    if (audioSessionError) {
        [self sendResult:@{@"code": @"audio", @"message": [audioSessionError localizedDescription]} :nil :nil :nil];
        [self stop];
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
    if (error) {
        [self sendEventWithName:@"onSpeechError" body:error];
    }
    
    if (bestTranscription) {
        if ([isFinal boolValue]) {
            [self sendEventWithName:@"onSpeechResults" body:@{@"value":@[bestTranscription]} ];
        } else {
            [self sendEventWithName:@"onSpeechPartialResults" body:@{@"value":transcriptions} ];
        }
    } else if (transcriptions) {
        [self sendEventWithName:@"onSpeechPartialResults" body:@{@"value":transcriptions} ];
    }
    
    if ([isFinal boolValue]) {
        [self sendEventWithName:@"onSpeechRecognized" body: @{@"isFinal": isFinal}];
    }
}

- (void) stop {
    // Prevent additional tear-down calls
    if (self.isTearingDown || !self.sessionId) {
        return;
    }
    
    self.isTearingDown = YES;
    
    // Set back audio session category
    [self resetAudioSession];
    
    if (self.recognitionTask) {
        [self.recognitionTask cancel];
    }
    
    // Remove tap on bus
    if (self.audioEngine) {
        if (self.audioEngine.inputNode) {
            [self.audioEngine.inputNode removeTapOnBus:bus];
        }
        
        // Stop audio engine
        if (self.audioEngine.isRunning) {
            [self.audioEngine stop];
        }
    }
    
    self.sessionId = nil;
    self.isTearingDown = NO;
    
    // Emit onSpeechEnd event
    [self sendEventWithName:@"onSpeechEnd" body:nil];
}

- (void) reset {
    if (self.recognitionTask != nil) {
        [self.recognitionTask cancel];
        self.recognitionTask = nil;
    }
    
    self.recognitionRequest = nil;
    
    if (self.audioEngine != nil) {
        self.audioEngine = nil;
    }
    
    if (self.speechRecognizer != nil) {
        [self.speechRecognizer setDelegate:nil];
    }
}


// Called when the availability of the given recognizer changes
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    if (!available) {
        [self stop];
        [self sendResult:@{@"code": @"not_available"} :nil :nil :nil];
    }
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [self stop];
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
    if (self.isTearingDown || self.sessionId != nil) {
        resolve(@NO);
        return;
    }
    resolve(@YES);
}

RCT_EXPORT_METHOD(prepare:(NSString*)localeStr
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (self.sessionId != nil) {
        reject(@"recognizer_busy", @"Speech recognition already started!", nil);
        return;
    }
    
    if (self.isTearingDown) {
        reject(@"not_ready", @"Speech recognition is not ready", nil);
        return;
    };
    
    // Configure speech recognition options
    @try {
        if ([options objectForKey:@"recordingEnabled"]) {
            self.recordingEnabled = [RCTConvert BOOL:options[@"recordingEnabled"]];
        }
    } @catch (NSException *exception) {
        NSLog(@"[Error] - %@ %@", exception.name, exception.reason);
        self.recordingEnabled = false;
    } @finally {
        [self prepare:localeStr];
        resolve(nil);
    }
}

RCT_EXPORT_METHOD(startSpeech:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{    
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
                [self startRecognizing];
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
