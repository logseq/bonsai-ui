#!/bin/sh -e

prefix=$1

make install PROGRAMS=ocamlrun
cp ios-cc "${prefix}/ios-sysroot/bin/ios-cc"

host_ocamlrun=$(command -v ocamlrun)
export host_ocamlrun
for program in ocaml ocamlc.byte ocamlcmt ocamlcp ocamldep.byte ocamllex.byte \
               ocamlmklib ocamlmktop ocamlobjinfo.byte ocamlopt.byte \
               ocamloptp ocamlprof ocamlyacc; do
  if test -f "${prefix}/ios-sysroot/bin/${program}"; then
    perl -0pi -e 's|\A#![^\n]*\n|#!$ENV{host_ocamlrun}\n|' \
      "${prefix}/ios-sysroot/bin/${program}"
  fi
done

cp compilerlibs/ocamlcommon.cmxa compilerlibs/ocamlcommon.a \
   compilerlibs/ocamlbytecomp.cmxa compilerlibs/ocamlbytecomp.a \
   compilerlibs/ocamloptcomp.cmxa compilerlibs/ocamloptcomp.a \
   driver/main.cmx driver/main.o \
   driver/optmain.cmx driver/optmain.o \
   "${prefix}/ios-sysroot/lib/ocaml/compiler-libs"

for package in bigarray bytes compiler-libs dynlink findlib graphics runtime_events \
               stdlib str threads unix; do
  if test -f "${prefix}/lib/ocaml/${package}/META"; then
    mkdir -p "${prefix}/ios-sysroot/lib/${package}"
    cp "${prefix}/lib/ocaml/${package}/META" \
      "${prefix}/ios-sysroot/lib/${package}/META"
  fi
done

cp -f "${prefix}/ios-sysroot/lib/ocaml/runtime_events/"* \
  "${prefix}/ios-sysroot/lib/runtime_events/"

mkdir -p "${prefix}/lib/findlib.conf.d"
cp ios.conf "${prefix}/lib/findlib.conf.d"
