#import <UIKit/UIKit.h>

#include <stdio.h>

#import <caml/callback.h>
#import <caml/mlvalues.h>
#import <caml/startup.h>

@interface BonsaiSwiftUIProbeDelegate : UIResponder <UIApplicationDelegate>

@property(nonatomic, strong) UIWindow *window;

@end

@implementation BonsaiSwiftUIProbeDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  (void)launchOptions;

  const value *probe = caml_named_value("bonsai_swiftui.ios_probe");
  if (probe == NULL) {
    NSLog(@"BONSAI_SWIFTUI_IOS_PROBE_FAILURE missing callback");
    return NO;
  }

  value result = caml_callback_exn(*probe, Val_unit);
  if (Is_exception_result(result) || Long_val(result) != 42) {
    NSLog(@"BONSAI_SWIFTUI_IOS_PROBE_FAILURE invalid result");
    return NO;
  }

  NSLog(@"BONSAI_SWIFTUI_IOS_PROBE_OK result=42");
  fputs("BONSAI_SWIFTUI_IOS_PROBE_OK result=42\n", stdout);
  fflush(stdout);
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [[UIViewController alloc] init];
  self.window.backgroundColor = UIColor.systemBackgroundColor;
  [self.window makeKeyAndVisible];
  return YES;
}

@end

int main(int argc, char *argv[]) {
  char *ocaml_argv[] = {argv[0], NULL};
  caml_startup(ocaml_argv);
  return UIApplicationMain(
      argc,
      argv,
      nil,
      NSStringFromClass(BonsaiSwiftUIProbeDelegate.class));
}
