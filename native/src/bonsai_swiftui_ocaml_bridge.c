#include "bonsai_swiftui_ocaml_bridge.h"

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_once_t bs_ocaml_once = PTHREAD_ONCE_INIT;
static int bs_ocaml_initialized = 0;
static char bs_ocaml_initialization_error[256] = {0};

static const value *bs_create_callback = NULL;
static const value *bs_pump_callback = NULL;
static const value *bs_presentation_succeeded_callback = NULL;
static const value *bs_presentation_rejected_callback = NULL;
static const value *bs_destroy_callback = NULL;

static void bs_copy_error(char *destination,
                          size_t capacity,
                          const char *message) {
  size_t length;

  if (destination == NULL || capacity == 0) {
    return;
  }
  if (message == NULL) {
    destination[0] = '\0';
    return;
  }
  length = strlen(message);
  if (length >= capacity) {
    length = capacity - 1;
  }
  memcpy(destination, message, length);
  destination[length] = '\0';
}

static void bs_ocaml_initialize_once(void) {
  char *argv[] = {"bonsai_swiftui", NULL};
  value startup_result = caml_startup_exn(argv);

  if (Is_exception_result(startup_result)) {
    bs_copy_error(bs_ocaml_initialization_error,
                  sizeof(bs_ocaml_initialization_error),
                  "OCaml runtime initialization raised an exception");
    return;
  }
  bs_create_callback = caml_named_value("bonsai_swiftui.create");
  bs_pump_callback = caml_named_value("bonsai_swiftui.pump");
  bs_presentation_succeeded_callback =
      caml_named_value("bonsai_swiftui.presentation_succeeded");
  bs_presentation_rejected_callback =
      caml_named_value("bonsai_swiftui.presentation_rejected");
  bs_destroy_callback = caml_named_value("bonsai_swiftui.destroy");
  if (bs_create_callback == NULL || bs_pump_callback == NULL ||
      bs_presentation_succeeded_callback == NULL ||
      bs_presentation_rejected_callback == NULL ||
      bs_destroy_callback == NULL) {
    bs_copy_error(bs_ocaml_initialization_error,
                  sizeof(bs_ocaml_initialization_error),
                  "OCaml runtime callbacks are not registered");
    return;
  }
  bs_ocaml_initialized = 1;
  caml_release_runtime_system();
}

int bs_ocaml_bridge_initialize(char *error, size_t error_capacity) {
  if (pthread_once(&bs_ocaml_once, bs_ocaml_initialize_once) != 0) {
    bs_copy_error(error, error_capacity, "pthread_once failed");
    return 0;
  }
  if (!bs_ocaml_initialized) {
    bs_copy_error(error, error_capacity, bs_ocaml_initialization_error);
    return 0;
  }
  if (error != NULL && error_capacity != 0) {
    error[0] = '\0';
  }
  return 1;
}

static int bs_enter_ocaml(void) {
  int registered = caml_c_thread_register();
  caml_acquire_runtime_system();
  return registered;
}

static void bs_leave_ocaml(int registered) {
  caml_release_runtime_system();
  if (registered) {
    (void)caml_c_thread_unregister();
  }
}

static int bs_valid_tuple(value tuple, mlsize_t fields) {
  return Is_block(tuple) && Tag_val(tuple) == 0 && Wosize_val(tuple) == fields;
}

static int bs_status_from_value(value status, bs_status *result) {
  int code;

  if (!Is_long(status)) {
    return 0;
  }
  code = Int_val(status);
  if (code < BS_STATUS_OK || code > BS_STATUS_FATAL_ERROR) {
    return 0;
  }
  *result = (bs_status)code;
  return 1;
}

static int bs_error_code_from_value(value code_value,
                                    bs_error_code *result) {
  int code;

  if (!Is_long(code_value)) {
    return 0;
  }
  code = Int_val(code_value);
  if (code < BS_ERROR_NONE || code > BS_ERROR_INVALID_SCHEDULER_STATE) {
    return 0;
  }
  *result = (bs_error_code)code;
  return 1;
}

static int bs_copy_ocaml_bytes(value source,
                               uint8_t **destination,
                               size_t *length) {
  mlsize_t source_length;
  uint8_t *copy;

  if (!Is_block(source) || Tag_val(source) != String_tag) {
    return 0;
  }
  source_length = caml_string_length(source);
  if (source_length == 0) {
    *destination = NULL;
    *length = 0;
    return 1;
  }
  copy = (uint8_t *)malloc(source_length);
  if (copy == NULL) {
    return 0;
  }
  memcpy(copy, String_val(source), source_length);
  *destination = copy;
  *length = source_length;
  return 1;
}

static int bs_copy_ocaml_error(value source, char **destination) {
  mlsize_t source_length;
  char *copy;

  if (!Is_block(source) || Tag_val(source) != String_tag) {
    return 0;
  }
  source_length = caml_string_length(source);
  copy = (char *)malloc(source_length + 1);
  if (copy == NULL) {
    return 0;
  }
  memcpy(copy, String_val(source), source_length);
  copy[source_length] = '\0';
  *destination = copy;
  return 1;
}

static void bs_response_reset(bs_ocaml_response *response) {
  memset(response, 0, sizeof(*response));
  response->status = BS_STATUS_FATAL_ERROR;
  response->error_code = BS_ERROR_OCAML_EXCEPTION;
}

static void bs_response_failure(bs_ocaml_response *response,
                                const char *message) {
  size_t length = strlen(message);

  bs_ocaml_bridge_response_release(response);
  bs_response_reset(response);
  response->error = (char *)malloc(length + 1);
  if (response->error != NULL) {
    memcpy(response->error, message, length + 1);
  }
}

static bs_status bs_ocaml_bridge_create_locked(const uint8_t *config,
                                               size_t config_length,
                                               uint64_t *handle,
                                               char *error,
                                               size_t error_capacity) {
  CAMLparam0();
  CAMLlocal2(argument, result);
  bs_status status = BS_STATUS_FATAL_ERROR;
  const char *config_bytes =
      config_length == 0 ? "" : (const char *)config;

  argument = caml_alloc_initialized_string(config_length, config_bytes);
  result = caml_callback_exn(*bs_create_callback, argument);
  if (Is_exception_result(result)) {
    bs_copy_error(error, error_capacity, "OCaml create callback raised");
  } else if (!bs_valid_tuple(result, 3) ||
             !bs_status_from_value(Field(result, 0), &status) ||
             !Is_block(Field(result, 1)) ||
             Tag_val(Field(result, 1)) != Custom_tag ||
             !Is_block(Field(result, 2)) ||
             Tag_val(Field(result, 2)) != String_tag) {
    status = BS_STATUS_FATAL_ERROR;
    bs_copy_error(error, error_capacity, "OCaml create callback returned invalid data");
  } else {
    int64_t signed_handle = Int64_val(Field(result, 1));
    if (signed_handle <= 0) {
      status = BS_STATUS_FATAL_ERROR;
      bs_copy_error(error, error_capacity, "OCaml create returned an invalid handle");
    } else {
      *handle = (uint64_t)signed_handle;
      bs_copy_error(error,
                    error_capacity,
                    String_val(Field(result, 2)));
    }
  }
  CAMLreturnT(bs_status, status);
}

bs_status bs_ocaml_bridge_create(const uint8_t *config,
                                 size_t config_length,
                                 uint64_t *handle,
                                 char *error,
                                 size_t error_capacity) {
  int registered;
  bs_status status;

  if (!bs_ocaml_initialized || handle == NULL) {
    bs_copy_error(error, error_capacity, "OCaml bridge is not initialized");
    return BS_STATUS_FATAL_ERROR;
  }
  registered = bs_enter_ocaml();
  status = bs_ocaml_bridge_create_locked(config,
                                         config_length,
                                         handle,
                                         error,
                                         error_capacity);
  bs_leave_ocaml(registered);
  return status;
}

typedef enum bs_callback_kind {
  BS_CALLBACK_PUMP,
  BS_CALLBACK_PRESENTATION_SUCCEEDED,
  BS_CALLBACK_PRESENTATION_REJECTED
} bs_callback_kind;

static bs_status bs_call_output_callback_locked(
    const value *callback,
    bs_callback_kind kind,
    uint64_t handle,
    int64_t monotonic_now_ns,
    const uint8_t *input,
    size_t input_length,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bs_ocaml_response *response) {
  CAMLparam0();
  CAMLlocal5(handle_value,
             monotonic_value,
             input_value,
             presentation_value,
             revision_value);
  CAMLlocal1(result);
  value arguments[4];
  int argument_count;
  bs_status status = BS_STATUS_FATAL_ERROR;
  const char *input_bytes =
      input_length == 0 ? "" : (const char *)input;

  bs_response_reset(response);
  handle_value = caml_copy_int64((int64_t)handle);
  monotonic_value = caml_copy_int64(monotonic_now_ns);
  presentation_value = caml_copy_int64((int64_t)presentation_id);
  revision_value = caml_copy_int64((int64_t)revision);
  input_value = caml_alloc_initialized_string(input_length, input_bytes);
  arguments[0] = handle_value;
  if (kind == BS_CALLBACK_PUMP) {
    arguments[1] = monotonic_value;
    arguments[2] = input_value;
    argument_count = 3;
  } else {
    arguments[1] = presentation_value;
    arguments[2] = revision_value;
    if (kind == BS_CALLBACK_PRESENTATION_SUCCEEDED) {
      arguments[3] = monotonic_value;
    } else {
      arguments[3] = Val_int(rejection_reason);
    }
    argument_count = 4;
  }
  result = caml_callbackN_exn(*callback, argument_count, arguments);
  if (Is_exception_result(result)) {
    bs_response_failure(response, "OCaml runtime callback raised");
  } else if (!bs_valid_tuple(result, 6) ||
             !bs_status_from_value(Field(result, 0), &status) ||
             !bs_error_code_from_value(Field(result, 4),
                                       &response->error_code) ||
             !Is_block(Field(result, 2)) ||
             Tag_val(Field(result, 2)) != Custom_tag ||
             !Is_block(Field(result, 3)) ||
             Tag_val(Field(result, 3)) != Custom_tag) {
    bs_response_failure(response, "OCaml runtime callback returned invalid data");
    status = BS_STATUS_FATAL_ERROR;
  } else {
    response->status = status;
    response->presentation_id = (uint64_t)Int64_val(Field(result, 2));
    response->revision = (uint64_t)Int64_val(Field(result, 3));
    if (!bs_copy_ocaml_bytes(Field(result, 1),
                             &response->data,
                             &response->length) ||
        !bs_copy_ocaml_error(Field(result, 5), &response->error)) {
      bs_response_failure(response, "Failed to copy the OCaml runtime response");
      status = BS_STATUS_FATAL_ERROR;
    } else if (kind == BS_CALLBACK_PUMP &&
               status != BS_STATUS_FATAL_ERROR &&
               response->presentation_id == 0) {
      bs_response_failure(response, "OCaml pump returned no presentation token");
      status = BS_STATUS_FATAL_ERROR;
    } else if (kind != BS_CALLBACK_PUMP &&
               (response->presentation_id != 0 || response->revision != 0 ||
                response->length != 0)) {
      bs_response_failure(response,
                          "OCaml presentation callback returned unexpected output");
      status = BS_STATUS_FATAL_ERROR;
    }
  }
  CAMLreturnT(bs_status, status);
}

static bs_status bs_call_output_callback(const value *callback,
                                         bs_callback_kind kind,
                                         uint64_t handle,
                                         int64_t monotonic_now_ns,
                                         const uint8_t *input,
                                         size_t input_length,
                                         uint64_t presentation_id,
                                         uint64_t revision,
                                         int32_t rejection_reason,
                                         bs_ocaml_response *response) {
  int registered;
  bs_status status;

  if (!bs_ocaml_initialized || callback == NULL || response == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  registered = bs_enter_ocaml();
  status = bs_call_output_callback_locked(callback,
                                          kind,
                                          handle,
                                          monotonic_now_ns,
                                          input,
                                          input_length,
                                          presentation_id,
                                          revision,
                                          rejection_reason,
                                          response);
  bs_leave_ocaml(registered);
  return status;
}

bs_status bs_ocaml_bridge_pump(uint64_t handle,
                               int64_t monotonic_now_ns,
                               const uint8_t *input,
                               size_t input_length,
                               bs_ocaml_response *response) {
  return bs_call_output_callback(bs_pump_callback,
                                 BS_CALLBACK_PUMP,
                                 handle,
                                 monotonic_now_ns,
                                 input,
                                 input_length,
                                 0,
                                 0,
                                 0,
                                 response);
}

bs_status bs_ocaml_bridge_presentation_succeeded(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int64_t monotonic_now_ns,
    bs_ocaml_response *response) {
  return bs_call_output_callback(bs_presentation_succeeded_callback,
                                 BS_CALLBACK_PRESENTATION_SUCCEEDED,
                                 handle,
                                 monotonic_now_ns,
                                 NULL,
                                 0,
                                 presentation_id,
                                 revision,
                                 0,
                                 response);
}

bs_status bs_ocaml_bridge_presentation_rejected(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bs_ocaml_response *response) {
  return bs_call_output_callback(bs_presentation_rejected_callback,
                                 BS_CALLBACK_PRESENTATION_REJECTED,
                                 handle,
                                 0,
                                 NULL,
                                 0,
                                 presentation_id,
                                 revision,
                                 rejection_reason,
                                 response);
}

void bs_ocaml_bridge_response_release(bs_ocaml_response *response) {
  if (response == NULL) {
    return;
  }
  free(response->data);
  free(response->error);
  memset(response, 0, sizeof(*response));
}

static void bs_ocaml_bridge_destroy_locked(uint64_t handle) {
  CAMLparam0();
  CAMLlocal2(handle_value, result);

  handle_value = caml_copy_int64((int64_t)handle);
  result = caml_callback_exn(*bs_destroy_callback, handle_value);
  (void)result;
  CAMLreturn0;
}

void bs_ocaml_bridge_destroy(uint64_t handle) {
  int registered;

  if (!bs_ocaml_initialized || bs_destroy_callback == NULL) {
    return;
  }
  registered = bs_enter_ocaml();
  bs_ocaml_bridge_destroy_locked(handle);
  bs_leave_ocaml(registered);
}
