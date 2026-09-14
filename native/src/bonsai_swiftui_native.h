#ifndef BONSAI_SWIFTUI_NATIVE_H
#define BONSAI_SWIFTUI_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#define BS_EXPORT __attribute__((visibility("default")))

#ifdef __cplusplus
extern "C" {
#endif

typedef struct bs_runtime bs_runtime;

typedef int32_t bs_status;
typedef int32_t bs_error_code;

#define BS_STATUS_OK 0
#define BS_STATUS_RECOVERABLE_ERROR 1
#define BS_STATUS_FATAL_ERROR 2

#define BS_ERROR_NONE 0
#define BS_ERROR_PROTOCOL 1
#define BS_ERROR_REVISION_MISMATCH 2
#define BS_ERROR_DUPLICATE_KEY 3
#define BS_ERROR_UNSUPPORTED_NODE_KIND 4
#define BS_ERROR_INVALID_PROP 5
#define BS_ERROR_HANDLER_MISSING 6
#define BS_ERROR_STALE_EVENT 7
#define BS_ERROR_HOST_EFFECT_FAILURE 8
#define BS_ERROR_OCAML_EXCEPTION 9
#define BS_ERROR_SWIFT_RENDERER_EXCEPTION 10
#define BS_ERROR_LIFECYCLE_EXCEPTION 11
#define BS_ERROR_NATIVE_LIBRARY_LOADING_ERROR 12
#define BS_ERROR_INVALID_PRESENTATION 13
#define BS_ERROR_INVALID_MONOTONIC_TIME 14
#define BS_ERROR_INVALID_SCHEDULER_STATE 15

#define BS_REJECTION_DECODE_FAILED 0
#define BS_REJECTION_FRAME_VALIDATION_FAILED 1
#define BS_REJECTION_RENDERER_EPOCH_MISMATCH 2
#define BS_REJECTION_RENDERER_REVISION_MISMATCH 3

typedef struct bs_output_buffer {
  const uint8_t *data;
  size_t length;
  uint64_t presentation_id;
  uint64_t revision;
  bs_status status;
  bs_error_code error_code;
} bs_output_buffer;

BS_EXPORT uint16_t bs_abi_version_major(void);
BS_EXPORT uint16_t bs_abi_version_minor(void);
BS_EXPORT uint16_t bs_protocol_version_major(void);
BS_EXPORT uint16_t bs_protocol_version_minor(void);

BS_EXPORT bs_runtime *bs_runtime_create(const uint8_t *config,
                                        size_t config_length);

BS_EXPORT bs_status bs_runtime_pump(bs_runtime *runtime,
                                    int64_t monotonic_now_ns,
                                    const uint8_t *input,
                                    size_t input_length,
                                    bs_output_buffer *output);

BS_EXPORT bs_status bs_runtime_presentation_succeeded(
    bs_runtime *runtime,
    uint64_t presentation_id,
    uint64_t revision,
    int64_t monotonic_now_ns,
    bs_output_buffer *output);

BS_EXPORT bs_status bs_runtime_presentation_rejected(
    bs_runtime *runtime,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bs_output_buffer *output);

BS_EXPORT bs_status bs_runtime_get_last_error(bs_runtime *runtime,
                                              bs_output_buffer *output);

BS_EXPORT void bs_buffer_free(bs_runtime *runtime, const uint8_t *data);

BS_EXPORT size_t bs_runtime_outstanding_buffers(const bs_runtime *runtime);

BS_EXPORT void bs_runtime_destroy(bs_runtime *runtime);

#ifdef __cplusplus
}
#endif

#endif
