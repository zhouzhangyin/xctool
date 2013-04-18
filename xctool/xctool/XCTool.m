
#import "XCTool.h"
#import "XCToolUtil.h"

#import "Action.h"
#import "NSFileHandle+Print.h"
#import "Options.h"
#import "RawReporter.h"
#import "TaskUtil.h"
#import "TextReporter.h"
#import "XcodeSubjectInfo.h"

@implementation XCTool

- (id)init
{
  if (self = [super init]) {
    _exitStatus = 0;
  }
  return self;
}

- (void)printUsage
{
  [_standardError printString:@"usage: xctool [BASE OPTIONS] [ACTION [ACTION ARGUMENTS]] ...\n\n"];

  [_standardError printString:@"Examples:\n"];
  for (Class actionClass in [Options actionClasses]) {
    NSString *actionName = [actionClass name];
    NSArray *options = [actionClass options];

    NSMutableString *buffer = [NSMutableString string];

    for (NSDictionary *option in options) {
      if (option[kActionOptionParamName]) {
        [buffer appendFormat:@" [-%@ %@]", option[kActionOptionName], option[kActionOptionParamName]];
      } else {
        [buffer appendFormat:@" [-%@]", option[kActionOptionName]];
      }
    }

    [_standardError printString:@"    xctool [BASE OPTIONS] %@%@", actionName, buffer];
    [_standardError printString:@"\n"];
  }

  [_standardError printString:@"\n"];

  [_standardError printString:@"Base Options:\n"];
  [_standardError printString:@"%@", [Options actionUsage]];

  for (Class actionClass in [Options actionClasses]) {
    NSString *actionName = [actionClass name];
    NSString *actionUsage = [actionClass actionUsage];

    if (actionUsage.length > 0) {
      [_standardError printString:@"\n"];
      [_standardError printString:@"Options for '%@' action:\n", actionName];
      [_standardError printString:@"%@", actionUsage];
    }
  }

  [_standardError printString:@"\n"];
}

- (void)run
{
  Options *options = [[[Options alloc] init] autorelease];
  XcodeSubjectInfo *xcodeSubjectInfo = [[[XcodeSubjectInfo alloc] init] autorelease];

  NSString *errorMessage = nil;

  NSFileManager *fm = [NSFileManager defaultManager];
  if ([fm isReadableFileAtPath:@".xctool-args"]) {
    NSError *readError = nil;
    NSString *argumentsString = [NSString stringWithContentsOfFile:@".xctool-args"
                                                          encoding:NSUTF8StringEncoding
                                                             error:&readError];
    if (readError) {
      [_standardError printString:@"ERROR: Cannot read '.xctool-args' file: %@\n", [readError localizedFailureReason]];
      _exitStatus = 1;
      return;
    }

    NSError *JSONError = nil;
    NSArray *argumentsList = [NSJSONSerialization JSONObjectWithData:[argumentsString dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0
                                                               error:&JSONError];
    if (JSONError) {
      [_standardError printString:@"ERROR: couldn't parse json: %@: %@\n", argumentsString, [JSONError localizedDescription]];
      _exitStatus = 1;
      return;
    }

    [options consumeArguments:[NSMutableArray arrayWithArray:argumentsList] errorMessage:&errorMessage];
    if (errorMessage != nil) {
      [_standardError printString:@"ERROR: %@\n", errorMessage];
      _exitStatus = 1;
      return;
    }
  }

  [options consumeArguments:[NSMutableArray arrayWithArray:self.arguments] errorMessage:&errorMessage];
  if (errorMessage != nil) {
    [_standardError printString:@"ERROR: %@\n", errorMessage];
    [self printUsage];
    _exitStatus = 1;
    return;
  }

  if (options.showHelp) {
    [self printUsage];
    _exitStatus = 1;
    return;
  }

  if (options.showBuildSettings) {
    NSTask *task = TaskInstance();
    [task setLaunchPath:[XcodeDeveloperDirPath() stringByAppendingPathComponent:@"usr/bin/xcodebuild"]];
    [task setArguments:[[options xcodeBuildArgumentsForSubject] arrayByAddingObject:@"-showBuildSettings"]];
    [task setStandardOutput:_standardOutput];
    [task setStandardError:_standardError];
    [task launch];
    [task waitUntilExit];
    _exitStatus = [task terminationStatus];
    return;
  }

  if (![options validateOptions:&errorMessage xcodeSubjectInfo:xcodeSubjectInfo options:options]) {
    [_standardError printString:@"ERROR: %@\n\n", errorMessage];
    [self printUsage];
    _exitStatus = 1;
    return;
  }

  for (Reporter *reporter in options.reporters) {
    NSString *error = nil;
    if (![reporter openWithStandardOutput:_standardOutput error:&error]) {
      [_standardError printString:@"ERROR: %@\n\n", error];
      _exitStatus = 1;
      return;
    }
  }

  for (Action *action in options.actions) {
    [options.reporters makeObjectsPerformSelector:@selector(beginAction:) withObject:action];

    BOOL succeeded = [action performActionWithOptions:options xcodeSubjectInfo:xcodeSubjectInfo];

    for (Reporter *reporter in options.reporters) {
      [reporter endAction:action succeeded:succeeded];
    }

    if (!succeeded) {
      _exitStatus = 1;
      break;
    }
  }

  [options.reporters makeObjectsPerformSelector:@selector(close)];
}


@end