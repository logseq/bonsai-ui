#include "bonsai_swiftui_native.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(BS_WITH_OCAML)
#include "bonsai_swiftui_ocaml_bridge.h"
#endif

#define BS_PROTOCOL_MAJOR 10
#define BS_PROTOCOL_MINOR 0
#define BS_ABI_MAJOR 4
#define BS_ABI_MINOR 0

typedef struct bs_allocation {
  uint8_t *data;
  struct bs_allocation *next;
} bs_allocation;

struct bs_runtime {
  bs_allocation *allocations;
  size_t allocation_count;
  char last_error[256];
  char *last_error_detail;
  bs_error_code last_error_code;
#if defined(BS_WITH_OCAML)
  uint64_t backend_handle;
#endif
};

static void bs_store_error(bs_runtime *runtime,
                           bs_error_code error_code,
                           const char *message) {
  size_t length;
  int preserve_detail = 0;

  if (runtime == NULL) {
    return;
  }
  free(runtime->last_error_detail);
  runtime->last_error_detail = NULL;
  preserve_detail = error_code == BS_ERROR_DUPLICATE_KEY;
  if (message == NULL) {
    message = "bonsai_swiftui runtime error";
  }
  if (preserve_detail) {
    length = strlen(message);
    runtime->last_error_detail = (char *)malloc(length + 1);
    if (runtime->last_error_detail != NULL) {
      memcpy(runtime->last_error_detail, message, length + 1);
    }
  }
#if defined(NDEBUG)
  if (runtime->last_error_detail == NULL) {
    (void)snprintf(runtime->last_error,
                   sizeof(runtime->last_error),
                   "bonsai_swiftui runtime error %d",
                   (int)error_code);
  }
#else
  if (runtime->last_error_detail == NULL) {
    length = strlen(message);
    if (length >= sizeof(runtime->last_error)) {
      length = sizeof(runtime->last_error) - 1;
    }
    memcpy(runtime->last_error, message, length);
    runtime->last_error[length] = '\0';
  }
#endif
  runtime->last_error_code = error_code;
}

static void bs_output_reset(bs_output_buffer *output,
                            bs_status status,
                            bs_error_code error_code) {
  if (output == NULL) {
    return;
  }
  output->data = NULL;
  output->length = 0;
  output->presentation_id = 0;
  output->revision = 0;
  output->status = status;
  output->error_code = error_code;
}

static bs_status bs_set_error(bs_runtime *runtime,
                              bs_output_buffer *output,
                              bs_status status,
  bs_error_code error_code,
  const char *message) {
  bs_store_error(runtime, error_code, message);
  bs_output_reset(output, status, error_code);
  return status;
}

static uint8_t *bs_allocate_output(bs_runtime *runtime, size_t length) {
  bs_allocation *allocation;
  uint8_t *data;

  if (runtime == NULL || length == 0) {
    return NULL;
  }
  data = (uint8_t *)malloc(length);
  if (data == NULL) {
    return NULL;
  }
  allocation = (bs_allocation *)malloc(sizeof(bs_allocation));
  if (allocation == NULL) {
    free(data);
    return NULL;
  }
  allocation->data = data;
  allocation->next = runtime->allocations;
  runtime->allocations = allocation;
  runtime->allocation_count += 1;
  return data;
}

#if defined(BS_WITH_OCAML)
static bs_status bs_apply_ocaml_response(bs_runtime *runtime,
                                         bs_output_buffer *output,
                                         bs_status returned_status,
                                         bs_ocaml_response *response,
                                         int requires_presentation_id) {
  uint8_t *data = NULL;

  if (returned_status != response->status) {
    bs_ocaml_bridge_response_release(response);
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_FATAL_ERROR,
                        BS_ERROR_OCAML_EXCEPTION,
                        "OCaml bridge returned inconsistent status values");
  }
  if (response->error != NULL && response->error[0] != '\0') {
    bs_store_error(runtime, response->error_code, response->error);
  }
  if (returned_status == BS_STATUS_FATAL_ERROR) {
    if (response->error == NULL || response->error[0] == '\0') {
      bs_store_error(runtime,
                     response->error_code,
                     "OCaml runtime call failed without a diagnostic");
    }
    bs_output_reset(output, returned_status, response->error_code);
    bs_ocaml_bridge_response_release(response);
    return returned_status;
  }
  if (requires_presentation_id && response->presentation_id == 0) {
    bs_ocaml_bridge_response_release(response);
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_FATAL_ERROR,
                        BS_ERROR_OCAML_EXCEPTION,
                        "OCaml pump returned no presentation token");
  }
  if (response->length != 0 && response->data == NULL) {
    bs_ocaml_bridge_response_release(response);
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_FATAL_ERROR,
                        BS_ERROR_OCAML_EXCEPTION,
                        "OCaml bridge returned a null nonempty buffer");
  }
  if (response->length != 0) {
    data = bs_allocate_output(runtime, response->length);
    if (data == NULL) {
      bs_ocaml_bridge_response_release(response);
      return bs_set_error(runtime,
                          output,
                          BS_STATUS_FATAL_ERROR,
                          BS_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                          "Failed to allocate the runtime output buffer");
    }
    memcpy(data, response->data, response->length);
  }
  bs_output_reset(output, BS_STATUS_OK, BS_ERROR_NONE);
  output->data = data;
  output->length = response->length;
  output->presentation_id = response->presentation_id;
  output->revision = response->revision;
  output->status = returned_status;
  output->error_code = response->error_code;
  bs_ocaml_bridge_response_release(response);
  return returned_status;
}
#endif

uint16_t bs_abi_version_major(void) { return BS_ABI_MAJOR; }

uint16_t bs_abi_version_minor(void) { return BS_ABI_MINOR; }

uint16_t bs_protocol_version_major(void) { return BS_PROTOCOL_MAJOR; }

uint16_t bs_protocol_version_minor(void) { return BS_PROTOCOL_MINOR; }

bs_runtime *bs_runtime_create(const uint8_t *config, size_t config_length) {
  bs_runtime *runtime;

  if (config == NULL && config_length != 0) {
    return NULL;
  }
  runtime = (bs_runtime *)calloc(1, sizeof(bs_runtime));
  if (runtime == NULL) {
    return NULL;
  }
#if defined(BS_WITH_OCAML)
  {
    uint64_t handle = 0;
    char error[256] = {0};
    bs_status status;

    if (!bs_ocaml_bridge_initialize(error, sizeof(error))) {
      free(runtime);
      return NULL;
    }
    status = bs_ocaml_bridge_create(config,
                                    config_length,
                                    &handle,
                                    error,
                                    sizeof(error));
    if (status != BS_STATUS_OK || handle == 0) {
      free(runtime);
      return NULL;
    }
    runtime->backend_handle = handle;
  }
#else
  (void)config;
#endif
  memcpy(runtime->last_error, "No error", sizeof("No error"));
  runtime->last_error_code = BS_ERROR_NONE;
  return runtime;
}

bs_status bs_runtime_pump(bs_runtime *runtime,
                          int64_t monotonic_now_ns,
                          const uint8_t *input,
                          size_t input_length,
                          bs_output_buffer *output) {
  if (runtime == NULL || output == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  if (input == NULL && input_length != 0) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_RECOVERABLE_ERROR,
                        BS_ERROR_PROTOCOL,
                        "Input pointer is null for a nonempty batch");
  }
  if (monotonic_now_ns < 0) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_RECOVERABLE_ERROR,
                        BS_ERROR_INVALID_MONOTONIC_TIME,
                        "Monotonic time must be nonnegative");
  }
#if defined(BS_WITH_OCAML)
  {
    bs_ocaml_response response = {0};
    bs_status status =
        bs_ocaml_bridge_pump(runtime->backend_handle,
                             monotonic_now_ns,
                             input,
                             input_length,
                             &response);
    return bs_apply_ocaml_response(runtime, output, status, &response, 1);
  }
#else
  (void)input;
  return bs_set_error(runtime,
                      output,
                      BS_STATUS_FATAL_ERROR,
                      BS_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                      "OCaml runtime backend is not linked");
#endif
}

bs_status bs_runtime_shutdown_pump(bs_runtime *runtime,
                          int64_t monotonic_now_ns,
                          const uint8_t *input,
                          size_t input_length,
                          bs_output_buffer *output) {
  if (runtime == NULL || output == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  if (input == NULL && input_length != 0) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_RECOVERABLE_ERROR,
                        BS_ERROR_PROTOCOL,
                        "Input pointer is null for a nonempty batch");
  }
  if (monotonic_now_ns < 0) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_RECOVERABLE_ERROR,
                        BS_ERROR_INVALID_MONOTONIC_TIME,
                        "Monotonic time must be nonnegative");
  }
#if defined(BS_WITH_OCAML)
  {
    bs_ocaml_response response = {0};
    bs_status status =
        bs_ocaml_bridge_shutdown_pump(runtime->backend_handle,
                             monotonic_now_ns,
                             input,
                             input_length,
                             &response);
    return bs_apply_ocaml_response(runtime, output, status, &response, 0);
  }
#else
  (void)input;
  return bs_set_error(runtime,
                      output,
                      BS_STATUS_FATAL_ERROR,
                      BS_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                      "OCaml runtime backend is not linked");
#endif
}

bs_status bs_runtime_presentation_succeeded(bs_runtime *runtime,
                                            uint64_t presentation_id,
                                            uint64_t revision,
                                            int64_t monotonic_now_ns,
                                            bs_output_buffer *output) {
  if (runtime == NULL || output == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  if (presentation_id == 0) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_RECOVERABLE_ERROR,
                        BS_ERROR_INVALID_PRESENTATION,
                        "Presentation ID must be positive");
  }
  if (monotonic_now_ns < 0) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_RECOVERABLE_ERROR,
                        BS_ERROR_INVALID_MONOTONIC_TIME,
                        "Monotonic time must be nonnegative");
  }
#if defined(BS_WITH_OCAML)
  {
    bs_ocaml_response response = {0};
    bs_status status =
        bs_ocaml_bridge_presentation_succeeded(runtime->backend_handle,
                                               presentation_id,
                                               revision,
                                               monotonic_now_ns,
                                               &response);
    return bs_apply_ocaml_response(runtime, output, status, &response, 0);
  }
#else
  (void)presentation_id;
  (void)revision;
  (void)monotonic_now_ns;
  return bs_set_error(runtime,
                      output,
                      BS_STATUS_FATAL_ERROR,
                      BS_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                      "OCaml runtime backend is not linked");
#endif
}

bs_status bs_runtime_presentation_rejected(bs_runtime *runtime,
                                           uint64_t presentation_id,
                                           uint64_t revision,
                                           int32_t rejection_reason,
                                           bs_output_buffer *output) {
  if (runtime == NULL || output == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  if (presentation_id == 0 || rejection_reason < BS_REJECTION_DECODE_FAILED ||
      rejection_reason > BS_REJECTION_RENDERER_REVISION_MISMATCH) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_RECOVERABLE_ERROR,
                        BS_ERROR_INVALID_PRESENTATION,
                        "Invalid presentation rejection");
  }
#if defined(BS_WITH_OCAML)
  {
    bs_ocaml_response response = {0};
    bs_status status = bs_ocaml_bridge_presentation_rejected(
        runtime->backend_handle,
        presentation_id,
        revision,
        rejection_reason,
        &response);
    return bs_apply_ocaml_response(runtime, output, status, &response, 0);
  }
#else
  (void)presentation_id;
  (void)revision;
  (void)rejection_reason;
  return bs_set_error(runtime,
                      output,
                      BS_STATUS_FATAL_ERROR,
                      BS_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                      "OCaml runtime backend is not linked");
#endif
}

bs_status bs_runtime_get_last_error(bs_runtime *runtime,
                                    bs_output_buffer *output) {
  size_t length;
  uint8_t *data;
  const char *message;

  if (runtime == NULL || output == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  message = runtime->last_error_detail == NULL ? runtime->last_error
                                               : runtime->last_error_detail;
  length = strlen(message);
  data = bs_allocate_output(runtime, length);
  if (length != 0 && data == NULL) {
    return bs_set_error(runtime,
                        output,
                        BS_STATUS_FATAL_ERROR,
                        BS_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                        "Failed to allocate the error buffer");
  }
  if (length != 0) {
    memcpy(data, message, length);
  }
  bs_output_reset(output, BS_STATUS_OK, runtime->last_error_code);
  output->data = data;
  output->length = length;
  return BS_STATUS_OK;
}

void bs_buffer_free(bs_runtime *runtime, const uint8_t *data) {
  bs_allocation **cursor;

  if (runtime == NULL || data == NULL) {
    return;
  }
  cursor = &runtime->allocations;
  while (*cursor != NULL) {
    bs_allocation *allocation = *cursor;
    if (allocation->data == data) {
      *cursor = allocation->next;
      free(allocation->data);
      free(allocation);
      runtime->allocation_count -= 1;
      return;
    }
    cursor = &allocation->next;
  }
}

size_t bs_runtime_outstanding_buffers(const bs_runtime *runtime) {
  return runtime == NULL ? 0 : runtime->allocation_count;
}

void bs_runtime_destroy(bs_runtime *runtime) {
  bs_allocation *allocation;

  if (runtime == NULL) {
    return;
  }
#if defined(BS_WITH_OCAML)
  bs_ocaml_bridge_destroy(runtime->backend_handle);
#endif
  allocation = runtime->allocations;
  while (allocation != NULL) {
    bs_allocation *next = allocation->next;
    free(allocation->data);
    free(allocation);
    allocation = next;
  }
  free(runtime->last_error_detail);
  memset(runtime, 0, sizeof(bs_runtime));
  free(runtime);
}
