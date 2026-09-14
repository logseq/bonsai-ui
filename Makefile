.PHONY: build test viewport-type-test fmt protocol-generate protocol-check protocol-fixtures-generate protocol-fixtures-check native-test swift-test xcode-test native-object integration-test ios-toolchains ios-cross-probes ios-sdk-repository ci-contract ci-install-framework ci-install-consumers ci-install-ios-toolchain ci-ocaml ci-swift ci-macos ci-sanitizers ci-ios ci-ios-device clean

EXAMPLE ?= counter
SANITIZERS ?= undefined
BONSAI_SWIFTUI := $(CURDIR)/_build/default/bonsai_swiftui_tool/bin/main.exe
CONSUMERS := clock counter gallery host_effects host_navigation mail navigation network sqlite_worker text_input todo
export BONSAI_SWIFTUI_SOURCE_ROOT := $(CURDIR)
export OCAMLPATH := $(CURDIR)/_build/install/default/lib:$(OCAMLPATH)
CONSUMER_ROOTS := $(addprefix ./examples/,$(CONSUMERS))

build:
	dune build @all

test:
	dune runtest
	tool/check_viewport_types.sh

viewport-type-test:
	tool/check_viewport_types.sh

fmt:
	dune build @fmt

protocol-generate:
	dune exec protocol/generator/generate.exe --

protocol-check:
	dune exec protocol/generator/generate.exe -- --check

protocol-fixtures-generate:
	dune exec protocol/generator/generate_fixtures.exe --
	python3 tool/generate_input_fixtures.py

protocol-fixtures-check:
	dune exec protocol/generator/generate_fixtures.exe -- --check
	python3 tool/generate_input_fixtures.py --check

native-test:
	sh tool/test_native_runtime.sh

xcode-test: native-test
	python3 tool/test_swiftui_xcode_host.py

swift-test: native-test protocol-check xcode-test
	python3 tool/test_swift_completion.py
	python3 tool/test_native_fixture_commands.py
	python3 tool/run_swift_tests.py
	python3 protocol/generator/test_swift_generator.py
	python3 tool/test_swift_platforms.py
	python3 native/test/test_navigation_window.py
	python3 native/test/test_mail_window.py
	python3 native/test/test_clock_window.py
	python3 native/test/test_network_window.py
	python3 native/test/test_sqlite_worker_window.py
	python3 native/test/test_host_effects_window.py
	python3 native/test/test_notice_window.py
	python3 native/test/test_host_navigation_window.py
	python3 native/test/test_picker_window.py
	python3 native/test/test_menu_window.py
	python3 native/test/test_selection_catalog_window.py
	python3 native/test/test_search_window.py
	python3 native/test/test_table_window.py
	python3 native/test/test_carousel_window.py
	python3 native/test/test_multiple_selection_window.py
	python3 native/test/test_contextual_selection_window.py
	python3 native/test/test_tag_window.py
	python3 native/test/test_button_window.py
	python3 native/test/test_projection_window.py
	python3 native/test/test_opacity_window.py
	python3 native/test/test_workflow_window.py
	python3 native/test/test_disclosure_window.py
	python3 native/test/test_group_box_window.py
	python3 native/test/test_label_window.py
	python3 native/test/test_badge_window.py
	python3 native/test/test_hover_window.py
	python3 native/test/test_gesture_window.py
	python3 native/test/test_swipe_window.py
	python3 native/test/test_removal_window.py
	python3 native/test/test_slider_window.py

native-object:
	dune build bonsai_swiftui_tool/bin/main.exe
	cd examples/$(EXAMPLE) && $(BONSAI_SWIFTUI) build macos --profile debug

integration-test: swift-test
	dune build bonsai_swiftui_tool/bin/main.exe
	python3 tool/test_swiftui_cli.py
	python3 tool/test_swiftui_doctor.py
	python3 tool/test_swiftui_example_cli.py
	$(MAKE) installed-cli-test

.PHONY: installed-cli-test
installed-cli-test:
	dune build @install
	python3 tool/test_swiftui_installed_cli.py

ios-toolchains:
	tool/ios/setup_toolchain.sh all

ios-cross-probes: ios-toolchains
	tool/ios/build_probe.sh iphoneos

ios-sdk-repository:
	tool/ios/regenerate_sdk_repository.sh --write

.PHONY: ios-sdk-repository-test
ios-sdk-repository-test:
	python3 tool/test_ios_sdk_repository.py
	tool/ios/verify_runtime_closure.sh --check-lock-only
	tool/ios/verify_runtime_closure.sh --check-lock-only --lock vendor/opam-ios/supported-closure.lock

ci-contract:
	python3 tool/test_ios_device_preflight.py
	tool/test_ci_contract.sh
	tool/test_ios_closure_lock.sh
	tool/test_datascript_worker_contract.sh

ci-install-framework:
	opam install . --deps-only --with-test --yes
	opam install . --yes

ci-install-consumers: ci-install-framework
	opam install $(CONSUMER_ROOTS) --yes

ci-install-ios-toolchain:
	dune build bonsai_swiftui_tool/bin/main.exe
	@$(BONSAI_SWIFTUI) toolchain show iphoneos >/dev/null 2>&1 || $(BONSAI_SWIFTUI) toolchain install iphoneos
	$(BONSAI_SWIFTUI) toolchain verify iphoneos

ci-ocaml: ci-install-consumers
	dune build @all
	dune runtest
	tool/check_viewport_types.sh
	dune build @fmt
	dune exec protocol/generator/generate.exe -- --check
	dune exec protocol/generator/generate_fixtures.exe -- --check
	dune build --profile release ocaml/bench/runtime_bench.exe
	opam lint bonsai_swiftui.opam bonsai_swiftui_test.opam bonsai_swiftui_tool.opam
	@set -e; for consumer in $(CONSUMERS); do 	  (cd "examples/$$consumer" && dune build --root=. @all && dune runtest --root=.); 	done

ci-swift: ci-install-consumers swift-test protocol-fixtures-check
	dune build bonsai_swiftui_tool/bin/main.exe
	@set -e; for consumer in $(CONSUMERS); do \
	  (cd "examples/$$consumer" && $(BONSAI_SWIFTUI) sync-host --check); \
	done

ci-macos: ci-ocaml ci-swift
	dune build bonsai_swiftui_tool/bin/main.exe
	@set -e; for consumer in $(CONSUMERS); do \
	  for profile in debug profile release; do \
	    (cd "examples/$$consumer" && $(BONSAI_SWIFTUI) build macos --profile "$$profile"); \
	  done; \
	done

ci-ios: ci-install-ios-toolchain
	dune build bonsai_swiftui_tool/bin/main.exe
	@set -e; for consumer in $(CONSUMERS); do \
	  for profile in debug profile release; do \
	    (cd "examples/$$consumer" && $(BONSAI_SWIFTUI) build ios --profile "$$profile" --no-codesign); \
	  done; \
	done

ci-ios-device: ci-install-consumers ci-install-ios-toolchain
	@test -n "$(IOS_DEVICE_ID)" || (echo "IOS_DEVICE_ID is required" >&2; exit 1)
	@test -n "$(IOS_DEVELOPMENT_TEAM)" || (echo "IOS_DEVELOPMENT_TEAM is required" >&2; exit 1)
	@tool/ci/ios_device_preflight.sh "$(IOS_DEVICE_ID)"
	dune build bonsai_swiftui_tool/bin/main.exe
	cd examples/$(EXAMPLE) && $(BONSAI_SWIFTUI) run ios --profile debug --device "$(IOS_DEVICE_ID)" --development-team "$(IOS_DEVELOPMENT_TEAM)"

ci-sanitizers:
	mkdir -p _build/ci
	clang -std=c11 -Wall -Wextra -Werror -g -DBS_WITH_OCAML \
	  -fsanitize=$(SANITIZERS) -fno-omit-frame-pointer \
	  native/src/bonsai_swiftui_native.c native/test/mock_ocaml_bridge.c \
	  native/test/native_bridge_test.c -o _build/ci/native_bridge_sanitized
	_build/ci/native_bridge_sanitized

clean:
	dune clean
