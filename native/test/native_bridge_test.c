#include "../src/bonsai_swiftui_native.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

int bs_mock_destroy_count(void);
int bs_mock_pump_count(void);
int bs_mock_presentation_succeeded_count(void);
int bs_mock_presentation_rejected_count(void);
int64_t bs_mock_last_monotonic_now_ns(void);
uint64_t bs_mock_last_presentation_id(void);
uint64_t bs_mock_last_revision(void);
int32_t bs_mock_last_rejection_reason(void);
uint64_t bs_mock_last_destroyed_handle(void);

int main(void) {
  const uint8_t config[] = "counter";
  const uint8_t recoverable_input[] = {0xee};
  const uint8_t recoverable_without_token_input[] = {0xcc};
  const uint8_t fatal_duplicate_input[] = {0xdd};
  const uint8_t no_diff_input[] = {0};
  const char duplicate_diagnostic[] =
      "duplicate key \"journal-row-focus:duplicate\" in candidate children\n\n"
      "Widget tree path:\n  Native_widget[key=\"journal-list\"]\n\n"
      "Duplicate siblings:\n"
      "  child[1]: Focus_scope[key=\"journal-row-focus:duplicate\"]\n"
      "  child[2]: Focus_scope[key=\"journal-row-focus:duplicate\"]";
  bs_output_buffer output;
  bs_runtime *runtime =
      bs_runtime_create(config, sizeof(config) - 1);

  assert(runtime != NULL);
  assert(bs_abi_version_major() == 3);
  assert(bs_abi_version_minor() == 0);
  assert(bs_protocol_version_major() == 5);
  assert(bs_protocol_version_minor() == 0);
  assert(offsetof(bs_output_buffer, data) == 0);
  assert(offsetof(bs_output_buffer, length) > offsetof(bs_output_buffer, data));
  assert(offsetof(bs_output_buffer, presentation_id) >
         offsetof(bs_output_buffer, length));
  assert(offsetof(bs_output_buffer, revision) >
         offsetof(bs_output_buffer, presentation_id));
  assert(offsetof(bs_output_buffer, status) >
         offsetof(bs_output_buffer, revision));
  assert(offsetof(bs_output_buffer, error_code) >
         offsetof(bs_output_buffer, status));

  assert(bs_runtime_pump(runtime, 10, NULL, 0, &output) == BS_STATUS_OK);
  assert(output.status == BS_STATUS_OK);
  assert(output.error_code == BS_ERROR_NONE);
  assert(output.presentation_id == 7);
  assert(output.revision == 1);
  assert(output.length == 5);
  assert(memcmp(output.data, "frame", 5) == 0);
  assert(bs_mock_pump_count() == 1);
  assert(bs_mock_last_monotonic_now_ns() == 10);
  assert(bs_runtime_outstanding_buffers(runtime) == 1);
  bs_buffer_free(runtime, output.data);
  assert(bs_runtime_outstanding_buffers(runtime) == 0);

  assert(bs_runtime_presentation_succeeded(runtime, 7, 1, 20, &output) ==
         BS_STATUS_OK);
  assert(output.status == BS_STATUS_OK);
  assert(output.presentation_id == 0);
  assert(output.revision == 0);
  assert(output.length == 0);
  assert(output.data == NULL);
  assert(bs_mock_presentation_succeeded_count() == 1);
  assert(bs_mock_last_presentation_id() == 7);
  assert(bs_mock_last_revision() == 1);
  assert(bs_mock_last_monotonic_now_ns() == 20);

  assert(bs_runtime_pump(runtime,
                         30,
                         recoverable_input,
                         sizeof(recoverable_input),
                         &output) == BS_STATUS_RECOVERABLE_ERROR);
  assert(output.status == BS_STATUS_RECOVERABLE_ERROR);
  assert(output.error_code == BS_ERROR_STALE_EVENT);
  assert(output.presentation_id == 8);
  assert(output.revision == 2);
  assert(output.length == 11);
  assert(memcmp(output.data, "recoverable", 11) == 0);
  assert(bs_runtime_outstanding_buffers(runtime) == 1);
  bs_buffer_free(runtime, output.data);
  assert(bs_runtime_outstanding_buffers(runtime) == 0);

  assert(bs_runtime_presentation_rejected(
             runtime, 8, 2, BS_REJECTION_FRAME_VALIDATION_FAILED, &output) ==
         BS_STATUS_OK);
  assert(bs_mock_presentation_rejected_count() == 1);
  assert(bs_mock_last_presentation_id() == 8);
  assert(bs_mock_last_revision() == 2);
  assert(bs_mock_last_rejection_reason() ==
         BS_REJECTION_FRAME_VALIDATION_FAILED);

  assert(bs_runtime_pump(runtime,
                         40,
                         no_diff_input,
                         sizeof(no_diff_input),
                         &output) == BS_STATUS_OK);
  assert(output.presentation_id == 9);
  assert(output.revision == 2);
  assert(output.length == 0);
  assert(output.data == NULL);

  assert(bs_runtime_pump(runtime,
                         41,
                         fatal_duplicate_input,
                         sizeof(fatal_duplicate_input),
                         &output) == BS_STATUS_FATAL_ERROR);
  assert(output.status == BS_STATUS_FATAL_ERROR);
  assert(output.error_code == BS_ERROR_DUPLICATE_KEY);
  assert(output.presentation_id == 0);
  assert(output.revision == 0);
  assert(output.length == 0);
  assert(output.data == NULL);
  assert(bs_runtime_get_last_error(runtime, &output) == BS_STATUS_OK);
  assert(output.error_code == BS_ERROR_DUPLICATE_KEY);
  assert(output.length == strlen(duplicate_diagnostic));
  assert(memcmp(output.data, duplicate_diagnostic, output.length) == 0);
  bs_buffer_free(runtime, output.data);

  assert(bs_runtime_pump(runtime,
                         42,
                         recoverable_without_token_input,
                         sizeof(recoverable_without_token_input),
                         &output) == BS_STATUS_FATAL_ERROR);
  assert(output.status == BS_STATUS_FATAL_ERROR);
  assert(output.error_code == BS_ERROR_OCAML_EXCEPTION);
  assert(output.presentation_id == 0);
  assert(output.revision == 0);
  assert(output.length == 0);
  assert(output.data == NULL);
  assert(bs_runtime_get_last_error(runtime, &output) == BS_STATUS_OK);
#if defined(BS_TEST_RELEASE_RUNTIME)
  assert(output.length == strlen("bonsai_swiftui runtime error 9"));
  assert(memcmp(output.data,
                "bonsai_swiftui runtime error 9",
                output.length) == 0);
#else
  assert(output.length == strlen("OCaml pump returned no presentation token"));
  assert(memcmp(output.data,
                "OCaml pump returned no presentation token",
                output.length) == 0);
#endif
  bs_buffer_free(runtime, output.data);

  assert(bs_runtime_pump(runtime, -1, NULL, 0, &output) ==
         BS_STATUS_RECOVERABLE_ERROR);
  assert(output.error_code == BS_ERROR_INVALID_MONOTONIC_TIME);
  assert(bs_runtime_presentation_succeeded(runtime, 0, 0, 0, &output) ==
         BS_STATUS_RECOVERABLE_ERROR);
  assert(output.error_code == BS_ERROR_INVALID_PRESENTATION);

  assert(bs_runtime_pump(runtime, 50, NULL, 0, &output) == BS_STATUS_OK);
  assert(output.length == 5);
  assert(bs_runtime_outstanding_buffers(runtime) == 1);
  const uint8_t *stale_buffer = output.data;

  const uint8_t replacement_config[] = "replacement";
  bs_runtime *replacement =
      bs_runtime_create(replacement_config, sizeof(replacement_config) - 1);
  assert(replacement != NULL);

  assert(bs_runtime_pump(runtime, 60, NULL, 0, &output) ==
         BS_STATUS_FATAL_ERROR);
  assert(output.status == BS_STATUS_FATAL_ERROR);
  bs_buffer_free(runtime, stale_buffer);
  assert(bs_runtime_outstanding_buffers(runtime) == 0);

  bs_runtime_destroy(runtime);
  assert(bs_mock_destroy_count() == 1);
  assert(bs_mock_last_destroyed_handle() == 42);

  assert(bs_runtime_pump(replacement, 70, NULL, 0, &output) == BS_STATUS_OK);
  assert(output.length == 5);
  bs_buffer_free(replacement, output.data);
  bs_runtime_destroy(replacement);
  assert(bs_mock_destroy_count() == 2);
  assert(bs_mock_last_destroyed_handle() == 43);
  return 0;
}
