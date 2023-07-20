(*
SWIPL-OCaml

Copyright (C) 2021  Kiran Gopinathan

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)

open Base
open Stdio
module C = Configurator.V1

let write_sexp fn list_of_str =
  let data = sexp_of_list sexp_of_string list_of_str |> Sexp.to_string in
  Out_channel.write_all fn ~data

let write_flags file list_of_str =
  let data = String.concat list_of_str ~sep:" " in
  Out_channel.write_all file ~data

let swi_inc_dir, swi_lib_dir =
  let ic, oc = Unix.open_process "swipl --dump-runtime-variables" in
  let re1 = Str.regexp {|^PLBASE=\"\(.+\)\"|} in
  let re2 = Str.regexp {|^PLLIBDIR=\"\(.+\)\"|} in
  let d1, d2 = ref None, ref None in
  ( try 
    while true do 
      let s = Stdlib.input_line ic in
      if Str.string_match re1 s 0 then
        d1 := Some ("-I" ^ Str.matched_group 1 s ^ "/include")
      else if Str.string_match re2 s 0 then
        d2 := Some ("-L" ^ Str.matched_group 1 s)
    done
  with End_of_file -> () );
  let _ = Unix.close_process (ic, oc) in
  !d1, !d2

let () =
  C.main ~name:"swipl" (fun c ->
    let default : C.Pkg_config.package_conf =
      { libs   = ["-lswipl"; "-lffi";
                  (match swi_lib_dir with Some d -> d | None -> "-I/usr/lib") ]
      ; cflags = ["-O2"; "-Wall"; "-Wextra"; "-Wno-unused-parameter"; "-pthread";
                  (match swi_inc_dir with Some d -> d | None -> "-I/usr/lib/swi-prolog/include");
                  "-I/usr/lib/libffi-3.2.1/include"]
      }
    in
    let default_ffi : C.Pkg_config.package_conf =
      { libs   = ["-lffi"] ;
        cflags = ["-O2"; "-Wall"; "-Wextra"; "-Wno-unused-parameter";
                  (match swi_inc_dir with Some d -> d | None -> "-I/usr/lib/swi-prolog/include");
                  "-I/usr/include/x86_64-linux-gnu"; (* default ubuntu *)
                  "-I/usr/include"] (* default ubuntu *)
      }
    in
    let conf =
      match C.Pkg_config.get c with
      | None -> default
      | Some pc ->
         let get_config package default =
           Option.value (C.Pkg_config.query pc ~package) ~default in
         let libffi = get_config "libffi" default_ffi in
         let swipl = get_config "swipl" default in
         let  module P = C.Pkg_config in
         { libs = (libffi.P.libs @ swipl.P.libs);
           cflags = (libffi.P.cflags @ swipl.P.cflags) }
    in
    let os_type = C.ocaml_config_var_exn (C.create "") "system" in
    let ccopts =
      if Base.String.(os_type = "macosx") then [""]
      else ["-Wl,-no-as-needed"]
    in
    write_sexp "c_flags.sexp"         conf.cflags;
    write_sexp "c_library_flags.sexp" conf.libs;
    write_sexp "ccopts.sexp"          ccopts;
    write_flags "c_library_flags"     conf.libs;
    write_flags "c_flags"             conf.cflags)
