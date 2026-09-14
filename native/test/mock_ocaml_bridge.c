#include "../src/bonsai_swiftui_ocaml_bridge.h"

#include <stdlib.h>
#include <string.h>

static int destroy_count = 0;
static int pump_count = 0;
static int presentation_succeeded_count = 0;
static int presentation_rejected_count = 0;
static int64_t last_monotonic_now_ns = -1;
static uint64_t last_presentation_id = 0;
static uint64_t last_revision = 0;
static int32_t last_rejection_reason = -1;
static uint64_t current_handle = 0;
static uint64_t last_destroyed_handle = 0;
static int create_count = 0;

int bs_ocaml_bridge_initialize(char *error, size_t error_capacity) {
  (void)error;
  (void)error_capacity;
  return 1;
}

bs_status bs_ocaml_bridge_create(const uint8_t *config,
                                 size_t config_length,
                                 uint64_t *handle,
                                 char *error,
                                 size_t error_capacity) {
  const char first[] = "counter";
  const char replacement[] = "replacement";
  (void)error;
  (void)error_capacity;
  if (!((config_length == sizeof(first) - 1 &&
         memcmp(config, first, sizeof(first) - 1) == 0) ||
        (config_length == sizeof(replacement) - 1 &&
         memcmp(config, replacement, sizeof(replacement) - 1) == 0))) {
    return BS_STATUS_FATAL_ERROR;
  }
  *handle = (uint64_t)(42 + create_count);
  create_count += 1;
  current_handle = *handle;
  return BS_STATUS_OK;
}

static bs_status stale_handle(bs_ocaml_response *response) {
  const char message[] = "Unknown native runtime handle";
  response->error = (char *)malloc(sizeof(message));
  if (response->error == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  memcpy(response->error, message, sizeof(message));
  response->status = BS_STATUS_FATAL_ERROR;
  response->error_code = BS_ERROR_OCAML_EXCEPTION;
  return BS_STATUS_FATAL_ERROR;
}

static bs_status respond(bs_ocaml_response *response,
                         const char *payload,
                         uint64_t presentation_id,
                         uint64_t revision) {
  size_t length = strlen(payload);
  if (length == 0) {
    response->data = NULL;
  } else {
    response->data = (uint8_t *)malloc(length);
    if (response->data == NULL) {
      return BS_STATUS_FATAL_ERROR;
    }
    memcpy(response->data, payload, length);
  }
  response->length = length;
  response->presentation_id = presentation_id;
  response->revision = revision;
  response->error = NULL;
  response->status = BS_STATUS_OK;
  response->error_code = BS_ERROR_NONE;
  return BS_STATUS_OK;
}

static bs_status diagnostic_response(bs_ocaml_response *response,
                                     bs_status status,
                                     bs_error_code error_code,
                                     const char *message) {
  size_t length = strlen(message) + 1;
  response->data = NULL;
  response->length = 0;
  response->presentation_id = 0;
  response->revision = 0;
  response->error = (char *)malloc(length);
  if (response->error == NULL) {
    return BS_STATUS_FATAL_ERROR;
  }
  memcpy(response->error, message, length);
  response->status = status;
  response->error_code = error_code;
  return status;
}

bs_status bs_ocaml_bridge_pump(uint64_t handle,
                               int64_t monotonic_now_ns,
                               const uint8_t *input,
                               size_t input_length,
                               bs_ocaml_response *response) {
  if (handle != current_handle) {
    return stale_handle(response);
  }
  pump_count += 1;
  last_monotonic_now_ns = monotonic_now_ns;
  if (input_length == 1 && input != NULL && input[0] == 0xdd) {
    return diagnostic_response(
        response,
        BS_STATUS_FATAL_ERROR,
        BS_ERROR_DUPLICATE_KEY,
        "duplicate key \"journal-row-focus:duplicate\" in candidate children\n\n"
        "Widget tree path:\n  Native_widget[key=\"journal-list\"]\n\n"
        "Duplicate siblings:\n"
        "  child[1]: Focus_scope[key=\"journal-row-focus:duplicate\"]\n"
        "  child[2]: Focus_scope[key=\"journal-row-focus:duplicate\"]");
  }
  if (input_length == 1 && input != NULL && input[0] == 0xcc) {
    return diagnostic_response(response,
                               BS_STATUS_RECOVERABLE_ERROR,
                               BS_ERROR_STALE_EVENT,
                               "recoverable response without a token");
  }
  if (input_length == 1 && input != NULL && input[0] == 0xee) {
    bs_status status = respond(response, "recoverable", 8, 2);
    if (status != BS_STATUS_OK) {
      return status;
    }
    response->status = BS_STATUS_RECOVERABLE_ERROR;
    response->error_code = BS_ERROR_STALE_EVENT;
    response->error = (char *)malloc(sizeof("dropped input batch"));
    if (response->error == NULL) {
      bs_ocaml_bridge_response_release(response);
      return BS_STATUS_FATAL_ERROR;
    }
    memcpy(response->error, "dropped input batch", sizeof("dropped input batch"));
    return BS_STATUS_RECOVERABLE_ERROR;
  }
  if (input_length == 1 && input != NULL && input[0] == 0) {
    return respond(response, "", 9, 2);
  }
  return respond(response, "frame", 7, 1);
}

bs_status bs_ocaml_bridge_presentation_succeeded(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int64_t monotonic_now_ns,
    bs_ocaml_response *response) {
  if (handle != current_handle) {
    return stale_handle(response);
  }
  presentation_succeeded_count += 1;
  last_presentation_id = presentation_id;
  last_revision = revision;
  last_monotonic_now_ns = monotonic_now_ns;
  return respond(response, "", 0, 0);
}

bs_status bs_ocaml_bridge_presentation_rejected(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bs_ocaml_response *response) {
  if (handle != current_handle) {
    return stale_handle(response);
  }
  presentation_rejected_count += 1;
  last_presentation_id = presentation_id;
  last_revision = revision;
  last_rejection_reason = rejection_reason;
  return respond(response, "", 0, 0);
}

void bs_ocaml_bridge_response_release(bs_ocaml_response *response) {
  free(response->data);
  free(response->error);
  memset(response, 0, sizeof(*response));
}

void bs_ocaml_bridge_destroy(uint64_t handle) {
  last_destroyed_handle = handle;
  destroy_count += 1;
  if (handle == current_handle) {
    current_handle = 0;
  }
}

int bs_mock_destroy_count(void) { return destroy_count; }
int bs_mock_pump_count(void) { return pump_count; }
int bs_mock_presentation_succeeded_count(void) {
  return presentation_succeeded_count;
}
int bs_mock_presentation_rejected_count(void) {
  return presentation_rejected_count;
}
int64_t bs_mock_last_monotonic_now_ns(void) { return last_monotonic_now_ns; }
uint64_t bs_mock_last_presentation_id(void) { return last_presentation_id; }
uint64_t bs_mock_last_revision(void) { return last_revision; }
int32_t bs_mock_last_rejection_reason(void) { return last_rejection_reason; }
uint64_t bs_mock_last_destroyed_handle(void) { return last_destroyed_handle; }
