#ifndef BONSAI_SWIFTUI_OCAML_BRIDGE_H
#define BONSAI_SWIFTUI_OCAML_BRIDGE_H

#include "bonsai_swiftui_native.h"

typedef struct bs_ocaml_response {
  bs_status status;
  bs_error_code error_code;
  uint8_t *data;
  size_t length;
  uint64_t presentation_id;
  uint64_t revision;
  char *error;
} bs_ocaml_response;

int bs_ocaml_bridge_initialize(char *error, size_t error_capacity);

bs_status bs_ocaml_bridge_create(const uint8_t *config,
                                 size_t config_length,
                                 uint64_t *handle,
                                 char *error,
                                 size_t error_capacity);

bs_status bs_ocaml_bridge_pump(uint64_t handle,
                               int64_t monotonic_now_ns,
                               const uint8_t *input,
                               size_t input_length,
                               bs_ocaml_response *response);

bs_status bs_ocaml_bridge_presentation_succeeded(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int64_t monotonic_now_ns,
    bs_ocaml_response *response);

bs_status bs_ocaml_bridge_presentation_rejected(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bs_ocaml_response *response);

void bs_ocaml_bridge_response_release(bs_ocaml_response *response);
void bs_ocaml_bridge_destroy(uint64_t handle);

#endif
