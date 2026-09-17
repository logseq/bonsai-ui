"""Generate deterministic Xcode application hosts for the native Swift package."""

import hashlib
import json
import os
import re
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile
import xml.etree.ElementTree as ET


CONFIGURATIONS = ("Debug", "Profile", "Release")
PLATFORMS = {"macOS": ("macosx", "MACOS", "26.0"), "iOS": ("iphoneos", "IOS", "18.0")}


def write_if_changed(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    content = content.encode() if isinstance(content, str) else content
    if not path.is_file() or path.read_bytes() != content:
        path.write_bytes(content)


def openstep(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "".join(
            f"{indent}\t{json.dumps(key)} = {openstep(item, depth + 1)};\n"
            for key, item in sorted(value.items())
        ) + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join(
            f"{indent}\t{openstep(item, depth + 1)},\n" for item in value
        ) + indent + ")"
    return json.dumps(str(value), ensure_ascii=False)


# Framework requirements are deliberately independent from application inputs.
FRAMEWORK_ENTITLEMENTS = {"macos": {}, "ios": {}}


def owned_input(root, host, relative):
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Input ownership requires a relative path without parent traversal: {relative}")
    resolved = (root / path).resolve()
    if not resolved.is_relative_to(root) or resolved.is_relative_to(host):
        raise ValueError(f"Input ownership requires a file inside the application and outside generated output: {relative}")
    if not resolved.is_file():
        raise ValueError(f"Input is not a readable regular file: {relative}")
    return resolved


def typed_equal(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(typed_equal(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(typed_equal(a, b) for a, b in zip(left, right))
    return left == right


def entitlement_dictionary(path):
    data = path.read_bytes()
    try:
        if not data.startswith(b"bplist"):
            tree = ET.fromstring(data)
            for dictionary in tree.iter("dict"):
                children = list(dictionary)
                keys = [node.text for node in children[::2]]
                if any(node.tag != "key" for node in children[::2]) or len(keys) != len(set(keys)):
                    raise ValueError("duplicate or invalid XML dictionary keys")
        result = plistlib.loads(data)
        if not isinstance(result, dict):
            raise ValueError("expected a plist dictionary")
        return result
    except (ValueError, TypeError, ET.ParseError, plistlib.InvalidFileException) as error:
        raise ValueError(f"Invalid entitlement plist {path}: {error}") from error


def effective_entitlements(root, host, declarations):
    effective = {}
    for platform in ("macos", "ios"):
        inputs = declarations.get(platform, {})
        if inputs and set(inputs) != {p.lower() for p in CONFIGURATIONS}:
            raise ValueError(f"{platform}.entitlements requires debug, profile and release")
        for configuration in CONFIGURATIONS:
            profile = configuration.lower()
            values = entitlement_dictionary(owned_input(root, host, inputs[profile])) if inputs else {}
            for key, value in FRAMEWORK_ENTITLEMENTS[platform].items():
                if key in values and not typed_equal(values[key], value):
                    raise ValueError(f"Entitlement conflict: {platform} {profile} {key}")
                values[key] = value
            effective[platform, configuration] = plistlib.dumps(values, sort_keys=True)
    return effective


def normalized_url(url):
    return url.lower().rstrip("/").removesuffix(".git")


def read_package_lock(root, host, packages, required=False, matching=True):
    relative = "swift-packages/Package.resolved"
    source = root / relative
    if not source.exists() and not source.is_symlink():
        if required and packages:
            raise ValueError("Missing Swift package lock; run bonsai-swiftui resolve-packages")
        return None
    source = owned_input(root, host, relative)
    data = source.read_bytes()
    try:
        lock = json.loads(data)
        if lock["version"] not in (2, 3) or not isinstance(lock["pins"], list):
            raise ValueError("unsupported lock format")
        pins = lock["pins"]
        identities, locations = set(), set()
        for pin in pins:
            identity, location, state = pin["identity"], normalized_url(pin["location"]), pin["state"]
            if identity in identities or location in locations:
                raise ValueError("duplicate package pin")
            identities.add(identity)
            locations.add(location)
            if pin["kind"] != "remoteSourceControl" or not re.fullmatch(r"[0-9a-fA-F]{40}", state["revision"]):
                raise ValueError("invalid resolved revision")
            if state.get("branch"):
                raise ValueError("mutable branch pin")
        for package in packages if matching else []:
            pin = next((p for p in pins if normalized_url(p["location"]) == normalized_url(package["url"])), None)
            kind, value = next(iter(package["requirement"].items()))
            if pin is None or pin["state"].get("version" if kind == "exact" else "revision") != value:
                raise ValueError(f"stale pin for {package['id']}")
        return data
    except (ValueError, KeyError, TypeError, StopIteration) as error:
        raise ValueError(f"Invalid or stale {relative}: {error}; run bonsai-swiftui resolve-packages") from error


def generate_project(*, framework_root, application_root, host_directory, product_name,
                     bundle_identifiers, entitlements=None, swift_packages=(), ios_minimum_version="18.0",
                     development_team="", check=False, validate_only=False, inputs_only=False,
                     require_lock=False, refresh_lock=False, package_validation=False):
    framework_root = Path(framework_root).resolve()
    application_root = Path(application_root).resolve()
    host = Path(host_directory).resolve()
    project = host / f"{product_name}.xcodeproj"
    entitlements = entitlements or {}
    for platform in ("macos", "ios"):
        identifier = bundle_identifiers[platform]
        for suffix in ("", ".test-host", ".tests", ".ui-tests"):
            value = identifier + suffix
            if len(value) > 255 or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value):
                raise ValueError(f"Invalid bundle identifier: {value}")
    if not re.fullmatch(r"[1-9][0-9]*\.(0|[1-9][0-9]*)", ios_minimum_version) or int(ios_minimum_version.split(".")[0]) < 18:
        raise ValueError(f"Unsupported iOS minimum version: {ios_minimum_version}; framework minimum is 18.0")
    effective = effective_entitlements(application_root, host, entitlements)
    lock = read_package_lock(application_root, host, swift_packages, require_lock, matching=not refresh_lock)
    if inputs_only:
        return project
    objects = {}
    outputs = {}

    def emit(path, content):
        outputs[path] = content.encode() if isinstance(content, str) else content

    def add(key, isa, **attributes):
        identifier = hashlib.sha256(key.encode()).hexdigest()[:24].upper()
        objects[identifier] = {"isa": isa, **attributes}
        return identifier

    def file(path, kind):
        relative = os.path.relpath(path, host)
        return add(f"file/{relative}", "PBXFileReference", lastKnownFileType=kind,
                   path=relative, sourceTree="<group>")

    def configurations(key, settings, application_platform=None):
        entries = []
        for configuration in CONFIGURATIONS:
            entries.append(add(
                f"{key}/{configuration}", "XCBuildConfiguration", name=configuration,
                buildSettings={
                    **settings,
                    **({"CODE_SIGN_ENTITLEMENTS": f"Entitlements/{application_platform}/{configuration}.entitlements"} if application_platform else {}),
                    "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O",
                    "GCC_OPTIMIZATION_LEVEL": "0" if configuration == "Debug" else "s",
                    "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym",
                    "ENABLE_TESTABILITY": "YES" if configuration == "Debug" else "NO",
                },
            ))
        return add(f"{key}/configurations", "XCConfigurationList", buildConfigurations=entries,
                   defaultConfigurationIsVisible="0", defaultConfigurationName="Debug")

    if package_validation:
        probe = host / "PackageValidation.swift"
        emit(probe, 'import SwiftUI\n@main struct PackageValidation: App { var body: some Scene { WindowGroup { Text("Package validation") } } }\n')
        source_files = [file(probe, "sourcecode.swift")]
    else:
        source_files = [file(path, "sourcecode.swift") for path in sorted((application_root / "swift").glob("*.swift"))]
    if not source_files:
        raise ValueError(f"No Swift application sources in {application_root / 'swift'}")
    test_files = [] if package_validation else [file(path, "sourcecode.swift") for path in sorted((application_root / "apple-tests").glob("*.swift"))]
    resources = []
    resource_directory = application_root / "resources"
    if resource_directory.is_dir() and not package_validation:
        for path in sorted(resource_directory.iterdir()):
            kind = "folder.assetcatalog" if path.suffix == ".xcassets" else "folder" if path.is_dir() else "file"
            resources.append(file(path, kind))
    package = add("package", "XCLocalSwiftPackageReference", relativePath=os.path.relpath(framework_root, host))
    remote_packages = {}
    for dependency in sorted(swift_packages, key=lambda p: p["id"]):
        kind, value = next(iter(dependency["requirement"].items()))
        requirement = {"kind": "exactVersion", "version": value} if kind == "exact" else {"kind": "revision", "revision": value}
        remote_packages[dependency["id"]] = add(f"remote-package/{dependency['id']}", "XCRemoteSwiftPackageReference",
                                               repositoryURL=dependency["url"], requirement=requirement)
    targets, products, schemes, test_host_files, ui_test_files = [], [], [], [], []

    for platform, (sdk, macho, minimum) in PLATFORMS.items():
        if platform == "iOS":
            minimum = ios_minimum_version
        target_name = f"{product_name}-{platform}"
        platform_ui_files = [] if package_validation else [file(path, "sourcecode.swift") for path in sorted(
            (application_root / "apple-ui-tests" / platform.lower()).glob("*.swift"))]
        ui_test_files.extend(platform_ui_files)
        metadata = {
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
        }
        if platform == "macOS":
            metadata.update(LSMinimumSystemVersion=minimum, NSHighResolutionCapable=True)
        else:
            metadata.update(
                LSRequiresIPhoneOS=True, UILaunchScreen={},
                UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes": False},
                UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
            )
            metadata["UISupportedInterfaceOrientations~ipad"] = [
                "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
            ]
        emit(host / f"Info-{platform}.plist", plistlib.dumps(metadata))
        for configuration in CONFIGURATIONS:
            emit(host / f"Entitlements/{platform}/{configuration}.entitlements", effective[platform.lower(), configuration])
        emit(host / f"Entitlements/{platform}/TestHost.entitlements", plistlib.dumps({}))
        settings = {
            "ARCHS": "arm64", "ONLY_ACTIVE_ARCH": "NO", "SDKROOT": sdk,
            "SUPPORTED_PLATFORMS": sdk, "SUPPORTS_MACCATALYST": "NO",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "MACOSX_DEPLOYMENT_TARGET": "26.0", "IPHONEOS_DEPLOYMENT_TARGET": ios_minimum_version,
            "SWIFT_VERSION": "6.0", "CLANG_ENABLE_MODULES": "YES",
            "SWIFT_INCLUDE_PATHS": ["$(inherited)", f'"$(PROJECT_DIR)/{os.path.relpath(framework_root / "native/src", host)}"'],
            "OTHER_LDFLAGS": ["$(inherited)", f'"$(PROJECT_DIR)/Native/{sdk}/$(CONFIGURATION)/runtime.complete.o"',
                              "-framework", "CoreFoundation", "-framework", "Security",
                              "-lpthread", '@"$(DERIVED_FILE_DIR)/runtime-system-libraries.rsp"', "-Wl,-no_compact_unwind"],
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@executable_path/Frameworks", "@loader_path/Frameworks"],
            "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": development_team,
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        }
        if platform == "macOS":
            settings["CODE_SIGN_IDENTITY"] = "-"
        else:
            settings["TARGETED_DEVICE_FAMILY"] = "1,2"

        def target(name, sources, kind="application"):
            is_test = kind in ("runtime-test", "ui-test")
            links_runtime = not package_validation and kind in ("application", "runtime-test")
            suffix = "xctest" if is_test else "app"
            output_name = product_name if kind == "application" else name
            product = add(f"{name}/product", "PBXFileReference", explicitFileType="wrapper.cfbundle" if is_test else "wrapper.application",
                          path=f"{output_name}.{suffix}", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex="0")
            products.append(product)
            package_products, package_links = [], []
            if links_runtime:
                package_product = add(f"{name}/package-product", "XCSwiftPackageProductDependency", productName="BonsaiSwiftUI")
                package_products.append(package_product)
                package_links.append(add(f"{name}/package-link", "PBXBuildFile", productRef=package_product))
            if kind == "application":
                for dependency in sorted(swift_packages, key=lambda p: p["id"]):
                    for selection in sorted(dependency["products"], key=lambda p: p["name"]):
                        if platform.lower() not in selection["platforms"]:
                            continue
                        key = f"{name}/remote/{dependency['id']}/{selection['name']}"
                        reference = add(key, "XCSwiftPackageProductDependency", package=remote_packages[dependency["id"]], productName=selection["name"])
                        package_products.append(reference)
                        package_links.append(add(key + "/link", "PBXBuildFile", productRef=reference))
            source_builds = [add(f"{name}/source/{reference}", "PBXBuildFile", fileRef=reference) for reference in sources]
            resource_builds = [add(f"{name}/resource/{reference}", "PBXBuildFile", fileRef=reference) for reference in resources] if kind == "application" else []
            phases = []
            if links_runtime:
                phases.append(add(
                    f"{name}/verify", "PBXShellScriptBuildPhase", name="Verify native complete object",
                    buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0", files=[],
                    inputPaths=[f"$(PROJECT_DIR)/Native/{sdk}/$(CONFIGURATION)/runtime.complete.o"],
                    outputPaths=["$(DERIVED_FILE_DIR)/runtime-system-libraries.rsp"], alwaysOutOfDate="1", shellPath="/bin/sh",
                    shellScript='set -eu\n/bin/sh "$PROJECT_DIR"/' + shlex.quote(os.path.relpath(framework_root / "tool/ios/verify_complete_object.sh", host))
                    + f' "$PROJECT_DIR/Native/{sdk}/$CONFIGURATION/runtime.complete.o" {macho} {minimum} arm64\n'
                    + f'symbols=$(xcrun nm -uj "$PROJECT_DIR/Native/{sdk}/$CONFIGURATION/runtime.complete.o")\n'
                    + 'mkdir -p "$DERIVED_FILE_DIR"\n'
                    + ': > "$DERIVED_FILE_DIR/runtime-system-libraries.rsp"\n'
                    + 'if printf "%s\\n" "$symbols" | LC_ALL=C grep -Eq "^_sqlite3_[A-Za-z0-9_]+$"; then\n'
                    + '  printf "%s\\n" "-lsqlite3" > "$DERIVED_FILE_DIR/runtime-system-libraries.rsp"\n'
                    + 'fi\n',
                ))
            for phase, files in [("Sources", source_builds), ("Frameworks", package_links), ("Resources", resource_builds)]:
                phases.append(add(f"{name}/{phase}", f"PBX{phase}BuildPhase", files=files,
                                  buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0"))
            target_settings = {**settings, "PRODUCT_NAME": output_name,
                               "PRODUCT_BUNDLE_IDENTIFIER": bundle_identifiers[platform.lower()] + {
                                   "application": "", "runtime-host": ".test-host",
                                   "runtime-test": ".tests", "ui-test": ".ui-tests",
                               }[kind]}
            dependencies = []
            if not links_runtime:
                target_settings.pop("OTHER_LDFLAGS")
                target_settings.pop("SWIFT_INCLUDE_PATHS")
            if kind == "ui-test":
                target_settings.update(GENERATE_INFOPLIST_FILE="YES", TEST_TARGET_NAME=target_name)
                dependencies.append(add(f"{name}/app-dependency", "PBXTargetDependency", target=application))
            elif kind == "runtime-test":
                target_settings.update(GENERATE_INFOPLIST_FILE="YES", TEST_HOST="")
                if platform == "iOS":
                    target_settings.update(
                        TEST_HOST=f"$(BUILT_PRODUCTS_DIR)/{test_host_name}.app/{test_host_name}",
                        BUNDLE_LOADER="$(TEST_HOST)",
                    )
                    dependencies.append(add(f"{name}/host-dependency", "PBXTargetDependency", target=test_host))
            else:
                target_settings.update(INFOPLIST_FILE=f"Info-{platform}.plist", GENERATE_INFOPLIST_FILE="NO",
                                       CODE_SIGN_ENTITLEMENTS=f"Entitlements/{platform}/TestHost.entitlements")
            identifier = add(name, "PBXNativeTarget", name=name, productName=output_name, productReference=product,
                             productType=("com.apple.product-type.bundle.ui-testing" if kind == "ui-test" else
                                          "com.apple.product-type.bundle.unit-test" if is_test else "com.apple.product-type.application"),
                             buildConfigurationList=configurations(name, target_settings, platform if kind == "application" else None),
                             buildPhases=phases, buildRules=[], dependencies=dependencies, packageProductDependencies=package_products)
            targets.append(identifier)
            return identifier

        application = target(target_name, source_files)
        if test_files and platform == "iOS":
            test_host_name = product_name + "TestHost"
            test_host_source = host / "TestHost.swift"
            emit(test_host_source, '''import SwiftUI

@main
struct RuntimeTestHost: App {
  var body: some Scene {
    WindowGroup {
      Text("Runtime tests")
    }
  }
}
''')
            test_host_file = file(test_host_source, "sourcecode.swift")
            test_host_files.append(test_host_file)
            test_host = target(test_host_name, [test_host_file], kind="runtime-host")
        test_name = target_name + "Tests"
        tests = []
        if test_files:
            tests.append((test_name, target(test_name, test_files, kind="runtime-test")))
        if platform_ui_files:
            ui_test_name = target_name + "UITests"
            tests.append((ui_test_name, target(ui_test_name, platform_ui_files, kind="ui-test")))
        schemes.append((target_name, application, tests))

    product_group = add("products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
    main_group = add("main", "PBXGroup", children=source_files + test_files + test_host_files + ui_test_files + resources + [product_group], sourceTree="<group>")
    project_id = add("project", "PBXProject", attributes={"LastUpgradeCheck": "2610", "BuildIndependentTargetsInParallel": "YES"},
                     buildConfigurationList=configurations("project", {"ARCHS": "arm64"}), compatibilityVersion="Xcode 14.0",
                     developmentRegion="en", knownRegions=["en", "Base"], mainGroup=main_group,
                     productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets,
                     packageReferences=[package, *remote_packages.values()])
    emit(project / "project.pbxproj", "// !$*UTF8*$!\n" + openstep({
        "archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project_id,
    }) + "\n")

    for name, application, tests in schemes:
        scheme = ET.Element("Scheme", LastUpgradeVersion="2610", version="1.7")

        def reference(parent, identifier, blueprint, buildable):
            ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=identifier,
                          BuildableName=buildable, BlueprintName=blueprint, ReferencedContainer=f"container:{project.name}")

        build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES", buildArchitectures="Automatic")
        entries = ET.SubElement(build, "BuildActionEntries")
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
        reference(entry, application, name, f"{product_name}.app")
        action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
        testables = ET.SubElement(action, "Testables")
        for test_name, identifier in tests:
            testable = ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO")
            reference(testable, identifier, test_name, f"{test_name}.xctest")
        launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="NO")
        reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), application, name, f"{product_name}.app")
        profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Profile", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
        reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), application, name, f"{product_name}.app")
        ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
        ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
        ET.indent(scheme)
        emit(project / "xcshareddata/xcschemes" / f"{name}.xcscheme", ET.tostring(scheme, encoding="utf-8", xml_declaration=True))
    lock_projection = project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    if lock is not None and swift_packages:
        emit(lock_projection, lock)
    obsolete = [host / f"{platform}.entitlements" for platform in PLATFORMS]
    if lock_projection not in outputs:
        obsolete.append(lock_projection)
    obsolete = [p for p in obsolete if p.is_file()]
    if validate_only:
        return project
    changed = [path for path, content in outputs.items()
               if not path.is_file() or path.read_bytes() != content]
    if check and (changed or obsolete):
        raise ValueError("Generated Xcode host is out of date: " + ", ".join(str(path) for path in changed + obsolete))
    if not check:
        for path in obsolete:
            path.unlink()
        for path in changed:
            write_if_changed(path, outputs[path])
    return project


def resolve_packages(*, locked=False, **options):
    """Resolve both platform graphs in a disposable host before publishing anything."""
    root = Path(options["application_root"]).resolve()
    host = Path(options["host_directory"]).resolve()
    packages = options.get("swift_packages", ())
    options = {**options, "refresh_lock": not locked}
    generate_project(**options, validate_only=True, require_lock=locked)
    if not packages:
        return generate_project(**options, validate_only=True) if locked else generate_project(**options)
    lock_path = root / "swift-packages/Package.resolved"
    resolved_lock_path = lock_path.resolve()
    if not resolved_lock_path.is_relative_to(root) or resolved_lock_path.is_relative_to(host):
        raise ValueError("Package lock ownership requires a path inside the application and outside generated output")
    previous = read_package_lock(root, host, packages, required=locked, matching=locked)
    with tempfile.TemporaryDirectory(prefix="bonsai-package-resolution-") as directory:
        staging = Path(directory)
        project = generate_project(**{**options, "host_directory": staging / "host"}, require_lock=locked, package_validation=True)
        base = ["xcodebuild", "-project", str(project), "-clonedSourcePackagesDirPath", str(staging / "packages"),
                "-derivedDataPath", str(staging / "DerivedData"), "-disablePackageRepositoryCache"]
        flags = ["-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile", "-skipPackageUpdates"] if locked else []
        projection = project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        first_pins = None
        for platform in PLATFORMS:
            # Build an isolated SwiftUI probe with precisely the selected products.
            # Xcode resolution alone does not validate exported products, and
            # its modern build system does not implement -dry-run.
            destination = "platform=macOS,arch=arm64" if platform == "macOS" else "generic/platform=iOS"
            command = base + ["-scheme", options["product_name"] + "-" + platform,
                              "-configuration", "Debug", "-destination", destination]
            for operation in (["-resolvePackageDependencies"], ["CODE_SIGNING_ALLOWED=NO", "build"]):
                result = subprocess.run(command + flags + operation, text=True, capture_output=True, timeout=300)
                if result.returncode:
                    raise ValueError("Swift package resolution failed in staging" + ("; run bonsai-swiftui resolve-packages" if locked else "") + ":\n" + (result.stdout + result.stderr)[-16000:])
            if not projection.is_file():
                raise ValueError("Xcode did not produce Package.resolved")
            pins = json.loads(projection.read_bytes())["pins"]
            if first_pins is not None and pins != first_pins:
                raise ValueError("Platform package graphs disagree; no shared lock can be published")
            first_pins = pins
        resolved = projection.read_bytes()
        if locked:
            if json.loads(previous)["pins"] != json.loads(resolved)["pins"]:
                raise ValueError("Xcode changed locked pins; run bonsai-swiftui resolve-packages")
        else:
            write_if_changed(lock_path, resolved)
    return generate_project(**{**options, "refresh_lock": False})


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-root", required=True, type=Path)
    parser.add_argument("--application-root", required=True, type=Path)
    parser.add_argument("--host-directory", required=True, type=Path)
    parser.add_argument("--product-name", required=True)
    parser.add_argument("--macos-bundle-identifier", required=True)
    parser.add_argument("--ios-bundle-identifier", required=True)
    parser.add_argument("--ios-minimum-version", default="18.0")
    parser.add_argument("--entitlement", nargs=3, action="append", default=[])
    parser.add_argument("--swift-package", nargs=4, action="append", default=[])
    parser.add_argument("--swift-product", nargs=3, action="append", default=[])
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--inputs-only", action="store_true")
    parser.add_argument("--require-lock", action="store_true")
    parser.add_argument("--resolve-packages", action="store_true")
    parser.add_argument("--locked-preflight", action="store_true")
    parser.add_argument("--check", action="store_true")
    arguments = vars(parser.parse_args())
    arguments["bundle_identifiers"] = {p: arguments.pop(p + "_bundle_identifier") for p in ("macos", "ios")}
    entitlements = {}
    for platform, profile, path in arguments.pop("entitlement"):
        entitlements.setdefault(platform, {})[profile] = path
    arguments["entitlements"] = entitlements
    packages = {identity: {"id": identity, "url": url, "requirement": {kind: value}, "products": []}
                for identity, url, kind, value in arguments.pop("swift_package")}
    for identity, name, platforms in arguments.pop("swift_product"):
        packages[identity]["products"].append({"name": name, "platforms": platforms.split(",")})
    arguments["swift_packages"] = list(packages.values())
    resolve = arguments.pop("resolve_packages")
    locked = arguments.pop("locked_preflight")
    try:
        if resolve or locked:
            for name in ("check", "validate_only", "inputs_only", "require_lock"):
                arguments.pop(name)
            print(resolve_packages(**arguments, locked=locked))
        else:
            print(generate_project(**arguments))
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
