#define BS_WITH_OCAML

#include <TargetConditionals.h>
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR && !TARGET_OS_MACCATALYST
#include "bonsai_swiftui_ios_process_stubs.c"
#endif

#include "bonsai_swiftui_native.c"
#include "bonsai_swiftui_ocaml_bridge.c"

CAMLprim value bs_native_embed_link_anchor(value unit) {
  (void)unit;
  return Val_unit;
}
