#import <UIKit/UIKit.h>

#include <stdio.h>

#import <caml/alloc.h>
#import <caml/callback.h>
#import <caml/memory.h>
#import <caml/mlvalues.h>
#import <caml/startup.h>

static NSString *RunNetworkProbe(void) {
  CAMLparam0();
  CAMLlocal3(certificateValue, privateKeyValue, result);

  const value *probe = caml_named_value("bonsai_swiftui.network_spike_device_probe");
  if (probe == NULL) {
    CAMLreturnT(NSString *, @"FAIL missing OCaml callback");
  }

  NSBundle *bundle = NSBundle.mainBundle;
  NSString *certificatePath = [bundle pathForResource:@"localhost-cert" ofType:@"pem"];
  NSString *privateKeyPath = [bundle pathForResource:@"localhost-key" ofType:@"pem"];
  NSError *error = nil;
  NSString *certificate = [NSString stringWithContentsOfFile:certificatePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
  if (certificate == nil) {
    CAMLreturnT(NSString *, @"FAIL could not read test certificate");
  }
  NSString *privateKey = [NSString stringWithContentsOfFile:privateKeyPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
  if (privateKey == nil) {
    CAMLreturnT(NSString *, @"FAIL could not read test private key");
  }

  certificateValue = caml_copy_string(certificate.UTF8String);
  privateKeyValue = caml_copy_string(privateKey.UTF8String);
  result = caml_callback2_exn(*probe, certificateValue, privateKeyValue);
  if (Is_exception_result(result)) {
    CAMLreturnT(NSString *, @"FAIL uncaught OCaml callback exception");
  }

  NSString *output = [NSString stringWithUTF8String:String_val(result)];
  CAMLreturnT(NSString *, output ?: @"FAIL OCaml callback returned invalid UTF-8");
}

@interface BonsaiSwiftUINetworkProbeDelegate : UIResponder <UIApplicationDelegate>

@property(nonatomic, strong) UIWindow *window;

@end

@implementation BonsaiSwiftUINetworkProbeDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  (void)launchOptions;

  NSString *result = RunNetworkProbe();
  NSString *marker = [result hasPrefix:@"OK "]
      ? [NSString stringWithFormat:@"BONSAI_SWIFTUI_NETWORK_DEVICE_PROBE_OK %@", result]
      : [NSString stringWithFormat:@"BONSAI_SWIFTUI_NETWORK_DEVICE_PROBE_FAILURE %@", result];
  NSLog(@"%@", marker);
  fprintf(stdout, "%s\n", marker.UTF8String);
  fflush(stdout);

  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [[UIViewController alloc] init];
  self.window.backgroundColor = UIColor.systemBackgroundColor;
  [self.window makeKeyAndVisible];
  return YES;
}

@end

int main(int argc, char *argv[]) {
  char *ocamlArgv[] = {argv[0], NULL};
  caml_startup(ocamlArgv);
  return UIApplicationMain(
      argc,
      argv,
      nil,
      NSStringFromClass(BonsaiSwiftUINetworkProbeDelegate.class));
}
