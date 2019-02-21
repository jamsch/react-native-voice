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
@property (nonatomic) BOOL continuous;
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
{
}


/** Returns "YES" if no errors had occurred */
-(BOOL) setupAudioSession {
    
    self.audioSession = [AVAudioSession sharedInstance];
    NSString* audioCategory = [self.audioSession category];
    // Set to PlayAndRecord
    if (![audioCategory isEqualToString:@"playAndRecord"]) {
        NSError* audioCategoryError = nil;
        [self.audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionMixWithOthers error: nil];
        if (audioCategoryError != nil) {
            [self sendResult:@{@"code": @"audio", @"message": [audioCategoryError localizedDescription]} :nil :nil :nil];
            return NO;
        }
        // Activate the audio session
        
        NSError* audioSessionError = nil;
        [self.audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&audioSessionError];
        
        if (audioSessionError != nil) {
            [self sendResult:@{@"code": @"audio", @"message": [audioSessionError localizedDescription]} :nil :nil :nil];
            return NO;
        }
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

- (void) setupAndStartRecognizing:(NSString*)localeStr {
    self.audioSession = [AVAudioSession sharedInstance];
    self.priorAudioCategory = [self.audioSession category];
    // Tear down resources before starting speech recognition..
    [self teardown];
    
    self.sessionId = [[NSUUID UUID] UUIDString];
    
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
        [self teardown];
        return;
    }
    
    if (self.audioEngine == nil) {
        self.audioEngine = [[AVAudioEngine alloc] init];
    }
    
    AVAudioInputNode* inputNode = self.audioEngine.inputNode;
    if (inputNode == nil) {
        [self sendResult:@{@"code": @"input"} :nil :nil :nil];
        [self teardown];
        return;
    }
    
    [self sendEventWithName:@"onSpeechStart" body:nil];
    
    // A recognition task represents a speech recognition session.
    // We keep a reference to the task so that it can be cancelled.
    NSString *taskSessionId = self.sessionId;
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        // Check if Session ID has changed
        if (taskSessionId && ![taskSessionId isEqualToString:self.sessionId]) {
            [self teardown];
            return;
        }
        
        if (error) {
            NSString *errorMessage = [NSString stringWithFormat:@"%ld/%@", error.code, [error localizedDescription]];
            [self sendResult:@{@"code": @"recognition_fail", @"message": errorMessage} :nil :nil :nil];
            [self teardown];
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
        if ((isFinal && !self.continuous) || self.recognitionTask.isCancelled || self.recognitionTask.isFinishing) {
            [self teardown];
        }
    }];
    
    AVAudioMixerNode *mixer = [[AVAudioMixerNode alloc] init];
    AVAudioFormat* recordingFormat = [mixer outputFormatForBus:0];
    
    if (self.recordingEnabled) {
        NSURL *fileURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"output.wav"];
        // Re-allocate output file
        NSError* recordError = nil;
        self.outputFile = [[AVAudioFile alloc] initForWriting:fileURL settings:recordingFormat.settings error:&recordError];
        if (recordError != nil) {
            [self sendResult:@{@"code": @"record_error", @"message": [recordError localizedDescription], @"domain": [recordError domain]} :nil :nil :nil];
            [self teardown];
            return;
        }
    }
    
    
    [self.audioEngine attachNode:mixer];
    
    // Start recording and append recording buffer to speech recognizer
    @try {
        [mixer installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
            // Todo: write recording buffer to file (if user opts in)
            if (self.recognitionRequest) {
                [self.recognitionRequest appendAudioPCMBuffer:buffer];
            }
            
            @try {
                if (self.recordingEnabled && self.outputFile) {
                    [self.outputFile writeFromBuffer:buffer error:nil];
                }
            } @catch (NSException *exception) {
                NSLog(@"[Error] - %@ %@", exception.name, exception.reason);
            } @finally {}
        }];
    } @catch (NSException *exception) {
        NSLog(@"[Error] - %@ %@", exception.name, exception.reason);
        [self sendResult:@{@"code": @"start_recording", @"message": [exception reason]} :nil :nil :nil];
        [self teardown];
        return;
    } @finally {}
    
    [self.audioEngine connect:inputNode to:mixer format:recordingFormat];
    [self.audioEngine prepare];
    NSError* audioSessionError = nil;
    [self.audioEngine startAndReturnError:&audioSessionError];
    if (audioSessionError) {
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

- (void) teardown {
    // Prevent additional tear-down calls
    if (self.isTearingDown || !self.sessionId) {
        return;
    }
    self.isTearingDown = YES;
    if (self.recognitionTask) {
        [self.recognitionTask cancel];
        self.recognitionTask = nil;
    }
    
    // End recognition request
    if (self.recognitionRequest) {
        [self.recognitionRequest endAudio];
    }
    
    // Remove tap on bus
    if (self.audioEngine) {
        if (self.audioEngine.inputNode) {
            [self.audioEngine.inputNode removeTapOnBus:0];
            [self.audioEngine.inputNode reset];
        }
        
        // Stop audio engine and dereference it for re-allocation
        if (self.audioEngine.isRunning) {
            [self.audioEngine stop];
            [self.audioEngine reset];
            self.audioEngine = nil;
        }
    }
    
    self.recognitionRequest = nil;
    self.sessionId = nil;
    self.isTearingDown = NO;
    
    // Emit onSpeechEnd event
    [self sendEventWithName:@"onSpeechEnd" body:nil];
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
    if (self.isTearingDown || self.sessionId != nil) {
        resolve(@NO);
        return;
    }
    resolve(@YES);
}

RCT_EXPORT_METHOD(startSpeech:(NSString*)localeStr
                  options:(NSDictionary *)options
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
    
    // Configure speech recognition options
    @try {
        if ([options objectForKey:@"continuous"]) {
            self.continuous = [RCTConvert BOOL:options[@"continuous"]];
        }
        if ([options objectForKey:@"recordingEnabled"]) {
            self.recordingEnabled = [RCTConvert BOOL:options[@"recordingEnabled"]];
        }
    } @catch (NSException *exception) {
        NSLog(@"[Error] - %@ %@", exception.name, exception.reason);
        self.continuous = false;
        self.recordingEnabled = false;
    } @finally {}
    
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
