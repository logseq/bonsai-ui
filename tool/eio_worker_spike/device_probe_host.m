#import <UIKit/UIKit.h>

#include <stdio.h>

#import <caml/alloc.h>
#import <caml/callback.h>
#import <caml/memory.h>
#import <caml/mlvalues.h>
#import <caml/startup.h>

static NSString *RunEioProbe(NSString *directory) {
  CAMLparam0();
  CAMLlocal2(directoryValue, result);

  const value *probe = caml_named_value("bonsai_swiftui.eio_worker_device_probe");
  if (probe == NULL) {
    CAMLreturnT(NSString *, @"FAIL missing OCaml callback");
  }

  directoryValue = caml_copy_string(directory.fileSystemRepresentation);
  result = caml_callback_exn(*probe, directoryValue);
  if (Is_exception_result(result)) {
    CAMLreturnT(NSString *, @"FAIL uncaught OCaml callback exception");
  }

  NSString *output = [NSString stringWithUTF8String:String_val(result)];
  CAMLreturnT(NSString *, output ?: @"FAIL OCaml callback returned invalid UTF-8");
}

static void EmitProbeResult(NSString *phase, NSString *directory) {
  NSString *result = RunEioProbe(directory);
  NSString *marker = [result hasPrefix:@"OK "]
      ? [NSString stringWithFormat:@"BONSAI_SWIFTUI_EIO_DEVICE_PROBE_%@ %@", phase, result]
      : [NSString stringWithFormat:@"BONSAI_SWIFTUI_EIO_DEVICE_PROBE_FAILURE phase=%@ %@", phase, result];
  NSLog(@"%@", marker);
  fprintf(stdout, "%s\n", marker.UTF8String);
  fflush(stdout);
}

@interface BonsaiSwiftUIEioProbeDelegate : UIResponder <UIApplicationDelegate>

@property(nonatomic, copy) NSString *probeDirectory;
@property(nonatomic, strong) UIWindow *window;

@end

@implementation BonsaiSwiftUIEioProbeDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  (void)launchOptions;

  NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"eio-worker-probe"];
  NSError *error = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&error]) {
    NSLog(@"BONSAI_SWIFTUI_EIO_DEVICE_PROBE_FAILURE directory=%@", error);
    return NO;
  }
  self.probeDirectory = directory;

  EmitProbeResult(@"OK", self.probeDirectory);

  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [[UIViewController alloc] init];
  self.window.backgroundColor = UIColor.systemBackgroundColor;
  [self.window makeKeyAndVisible];
  return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
  (void)application;
  NSLog(@"BONSAI_SWIFTUI_EIO_DEVICE_PROBE_BACKGROUND");
  fputs("BONSAI_SWIFTUI_EIO_DEVICE_PROBE_BACKGROUND\n", stdout);
  fflush(stdout);
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
  (void)application;
  EmitProbeResult(@"RESUME_OK", self.probeDirectory);
}

@end

int main(int argc, char *argv[]) {
  char *ocamlArgv[] = {argv[0], NULL};
  caml_startup(ocamlArgv);
  return UIApplicationMain(
      argc,
      argv,
      nil,
      NSStringFromClass(BonsaiSwiftUIEioProbeDelegate.class));
}
