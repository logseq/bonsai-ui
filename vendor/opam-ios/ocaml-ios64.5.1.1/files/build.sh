#!/bin/sh -e

host=$1

./configure \
  --host="$host" \
  --disable-debug-runtime \
  --disable-debugger \
  --disable-instrumented-runtime \
  --disable-ocamldoc \
  --disable-ocamltest \
  --disable-stdlib-manpages \
  --disable-shared \
  --with-pic \
  --without-odoc

make runtime/primitives runtime/sak SAK_CC=cc SAK_LINK='cc -o $(1) $(2)'

cp "$(command -v ocamlrun)" runtime/ocamlrun
cp -f Makefile.cross Makefile.config
cp -f s-ios.h runtime/caml/s.h
cp -f m-ios.h runtime/caml/m.h
sed -i.bak \
  's|^runtime_ASM_OBJECTS = .*|runtime_ASM_OBJECTS = $(addprefix runtime/,arm64.o)|' \
  Makefile.build_config
cc_config=$(sed -n 's/^CC=//p' Makefile.cross)
asm_config=$(sed -n 's/^ASM=//p' Makefile.cross | sed "s|\${CC}|${cc_config}|g")
packld_config=$(sed -n 's/^PACKLD=//p' Makefile.cross | sed 's/$(EMPTY)//g')
cflags_config=$(sed -n 's/^CFLAGS?=//p' Makefile.cross)
c_compiler_config="${OPAM_SWITCH_PREFIX}/ios-sysroot/bin/ios-cc"
ocamlc_cflags_config="-O2 -fno-strict-aliasing -fwrapv -pthread ${cflags_config}"
standard_library_config="${OPAM_SWITCH_PREFIX}/ios-sysroot/lib/ocaml"
printf '%s\n' \
  '#!/bin/sh' \
  "exec gcc ${cflags_config} \"\$@\"" \
  >ios-cc
chmod +x ios-cc
export \
  asm_config \
  c_compiler_config \
  ocamlc_cflags_config \
  packld_config \
  standard_library_config
perl -0pi -e '
  s/^let standard_library_default = .*/let standard_library_default = {|$ENV{standard_library_config}|}/m;
  s/^let c_compiler = .*/let c_compiler = {|$ENV{c_compiler_config}|}/m;
  s/^let ocamlc_cflags = .*/let ocamlc_cflags = {|$ENV{ocamlc_cflags_config}|}/m;
  s/^let ocamlopt_cflags = .*/let ocamlopt_cflags = {|$ENV{ocamlc_cflags_config}|}/m;
  s/^let native_pack_linker = .*/let native_pack_linker = {|$ENV{packld_config}|}/m;
  s/^let native_compiler = .*/let native_compiler = true/m;
  s/^let architecture = .*/let architecture = {|arm64|}/m;
  s/^let system = .*/let system = {|macosx|}/m;
  s/^let asm = .*/let asm = {|$ENV{asm_config}|}/m;
  s/^let asm_cfi_supported = .*/let asm_cfi_supported = true/m;
' utils/config.generated.ml
rm -f utils/config.ml utils/config_main.ml

make coldstart coreall ocaml otherlibraries \
  runtimeopt ocamlopt libraryopt otherlibrariesopt \
  compilerlibs/ocamlcommon.cmxa compilerlibs/ocamlbytecomp.cmxa \
  compilerlibs/ocamloptcomp.cmxa driver/main.cmx driver/optmain.cmx \
  runtime_PROGRAMS= \
  OCAMLRUN=ocamlrun \
  NEW_OCAMLRUN=ocamlrun
