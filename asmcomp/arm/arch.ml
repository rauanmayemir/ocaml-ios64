(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                 Benedikt Meurer, University of Siegen                  *)
(*                                                                        *)
(*   Copyright 1998 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*   Copyright 2012 Benedikt Meurer.                                      *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* Specific operations for the ARM processor *)

open Format

(* EABI is actually GNU EABI *)
type abi = EABI | EABI_HF | EABI_APPLE
type arch = ARMv4 | ARMv5 | ARMv5TE | ARMv6 | ARMv6T2 | ARMv7 | ARMv7s
type fpu = Soft | VFPv2 | VFPv3_D16 | VFPv3

let abi =
  match Config.system with
    "linux_eabi" | "freebsd" -> EABI
  | "linux_eabihf" | "netbsd" -> EABI_HF
  | "macosx" -> EABI_APPLE
  | _ -> assert false

let string_of_arch = function
    ARMv4   -> "armv4"
  | ARMv5   -> "armv5"
  | ARMv5TE -> "armv5te"
  | ARMv6   -> "armv6"
  | ARMv6T2 -> "armv6t2"
  | ARMv7   -> "armv7"
  | ARMv7s  -> "armv7s"  (* = armv7 + div *)

let string_of_fpu = function
    Soft      -> "soft"
  | VFPv2     -> "vfpv2"
  | VFPv3_D16 -> "vfpv3-d16"
  | VFPv3     -> "vfpv3"

(* Machine-specific command-line options *)

let (arch, fpu, thumb, supp_pic, supp_pie) =
  let (def_arch, def_fpu, def_thumb, supp_pic, supp_pie) =
    begin match abi, Config.model with
    (* Defaults for architecture, FPU, Thumb, PIC and PIE *)
      EABI,       "armv5"    -> ARMv5,   Soft,      false, true,  false
    | EABI,       "armv5te"  -> ARMv5TE, Soft,      false, true,  false
    | EABI,       "armv6"    -> ARMv6,   Soft,      false, true,  false
    | EABI,       "armv6t2"  -> ARMv6T2, Soft,      false, true,  false
    | EABI,       "armv7"    -> ARMv7,   Soft,      false, true,  false
    | EABI,       "armv7s"   -> ARMv7,   Soft,      false, true,  false
    | EABI,       _          -> ARMv4,   Soft,      false, true,  false
    | EABI_HF,    "armv6t2"  -> ARMv6,   VFPv2,     true,  true,  false
    | EABI_HF,    "armv7"    -> ARMv7,   VFPv3_D16, true,  true,  false
    | EABI_HF,    "armv7s"   -> ARMv7s,  VFPv3_D16, true,  true,  false
    | EABI_HF,    _          -> ARMv6,   VFPv2,     false, true,  false
    | EABI_APPLE, "armv7"    -> ARMv7,   VFPv3,     true,  false, true
    | EABI_APPLE, "armv7s"   -> ARMv7s,  VFPv3,     true,  false, true
    | EABI_APPLE, _          -> ARMv6,   VFPv2,     false, false, false
    end in
  (ref def_arch, ref def_fpu, ref def_thumb, supp_pic, supp_pie)

(* if pic/pie is supported the default is to enable it *)
let pic_code = ref supp_pic
let pie_code = ref supp_pie

let farch spec =
  arch := begin match spec with
             "armv4" when abi <> EABI_HF   -> ARMv4
           | "armv5" when abi <> EABI_HF   -> ARMv5
           | "armv5te" when abi <> EABI_HF -> ARMv5TE
           | "armv6"                       -> ARMv6
           | "armv6t2"                     -> ARMv6T2
           | "armv7"                       -> ARMv7
           | "armv7s"                      -> ARMv7s
           | spec -> raise (Arg.Bad ("wrong '-farch' option: " ^ spec))
  end

let have_hf =
  abi = EABI_HF || abi = EABI_APPLE

let ffpu spec =
  fpu := begin match spec with
            "soft" when not have_hf        -> Soft
          | "vfpv2" when have_hf           -> VFPv2
          | "vfpv3-d16" when have_hf       -> VFPv3_D16
          | "vfpv3" when have_hf           -> VFPv3
          | spec -> raise (Arg.Bad ("wrong '-ffpu' option: " ^ spec))
  end

let set_pic() =
  if not supp_pic then raise(Arg.Bad "PIC not supported for this model");
  pic_code := true

let set_pie() =
  if not supp_pie then raise(Arg.Bad "PIE not supported for this model");
  pie_code := true

let command_line_options =
  [ "-farch", Arg.String farch,
      "<arch>  Select the ARM target architecture"
      ^ " (default: " ^ (string_of_arch !arch) ^ ")";
    "-ffpu", Arg.String ffpu,
      "<fpu>  Select the floating-point hardware"
      ^ " (default: " ^ (string_of_fpu !fpu) ^ ")";
    "-fPIC", Arg.Unit set_pic,
      " Generate position-independent machine code for shared libs";
    "-fno-PIC", Arg.Clear pic_code,
      " Generate position-dependent machine code";
    "-fPIE", Arg.Unit set_pie,
      " Generate position-independent machine code for executables";
    "-fno-PIE", Arg.Clear pie_code,
      " Generate position-dependent machine code";
    "-fthumb", Arg.Set thumb,
      " Enable Thumb/Thumb-2 code generation"
      ^ (if !thumb then " (default)" else "");
    "-fno-thumb", Arg.Clear thumb,
      " Disable Thumb/Thumb-2 code generation"
      ^ (if not !thumb then " (default" else "")]

(* Addressing modes *)

type addressing_mode =
    Iindexed of int                     (* reg + displ *)

(* We do not support the reg + shifted reg addressing mode, because
   what we really need is reg + shifted reg + displ,
   and this is decomposed in two instructions (reg + shifted reg -> tmp,
   then addressing tmp + displ). *)

(* Specific operations *)

type specific_operation =
    Ishiftarith of arith_operation * shift_operation * int
  | Ishiftcheckbound of shift_operation * int
  | Irevsubimm of int
  | Imulhadd      (* multiply high and add *)
  | Imuladd       (* multiply and add *)
  | Imulsub       (* multiply and subtract *)
  | Inegmulf      (* floating-point negate and multiply *)
  | Imuladdf      (* floating-point multiply and add *)
  | Inegmuladdf   (* floating-point negate, multiply and add *)
  | Imulsubf      (* floating-point multiply and subtract *)
  | Inegmulsubf   (* floating-point negate, multiply and subtract *)
  | Isqrtf        (* floating-point square root *)
  | Ibswap of int (* endianess conversion *)

and arith_operation =
    Ishiftadd
  | Ishiftsub
  | Ishiftsubrev
  | Ishiftand
  | Ishiftor
  | Ishiftxor

and shift_operation =
    Ishiftlogicalleft
  | Ishiftlogicalright
  | Ishiftarithmeticright

let spacetime_node_hole_pointer_is_live_before _specific_op = false

(* Sizes, endianness *)

let big_endian = false

let size_addr = 4
let size_int = 4
let size_float = 8

let allow_unaligned_access = false

(* Behavior of division *)

let division_crashes_on_overflow = false

(* Operations on addressing modes *)

let identity_addressing = Iindexed 0

let offset_addressing (Iindexed n) delta = Iindexed(n + delta)

let num_args_addressing (Iindexed _) = 1

(* Printing operations and addressing modes *)

let print_addressing printreg addr ppf arg =
  match addr with
  | Iindexed n ->
      printreg ppf arg.(0);
      if n <> 0 then fprintf ppf " + %i" n

let shiftop_name = function
  | Ishiftlogicalleft -> "<<"
  | Ishiftlogicalright -> ">>u"
  | Ishiftarithmeticright -> ">>s"

let print_specific_operation printreg op ppf arg =
  match op with
    Ishiftarith(op, shiftop, amount) ->
      let (op1_name, op2_name) = match op with
          Ishiftadd -> ("", "+")
        | Ishiftsub -> ("", "-")
        | Ishiftsubrev -> ("-", "+")
        | Ishiftand -> ("", "&")
        | Ishiftor -> ("", "|")
        | Ishiftxor -> ("", "^") in
      fprintf ppf "%s%a %s (%a %s %i)"
        op1_name
        printreg arg.(0)
        op2_name
        printreg arg.(1)
        (shiftop_name shiftop)
        amount
  | Ishiftcheckbound(shiftop, amount) ->
      fprintf ppf "check (%a %s %i) > %a"
        printreg arg.(0)
        (shiftop_name shiftop)
        amount
        printreg arg.(1)
  | Irevsubimm n ->
      fprintf ppf "%i %s %a" n "-" printreg arg.(0)
  | Imulhadd ->
      fprintf ppf "%a *h %a) + %a"
        printreg arg.(0)
        printreg arg.(1)
        printreg arg.(2)
  | Imuladd ->
      fprintf ppf "(%a * %a) + %a"
        printreg arg.(0)
        printreg arg.(1)
        printreg arg.(2)
  | Imulsub ->
      fprintf ppf "-(%a * %a) + %a"
        printreg arg.(0)
        printreg arg.(1)
        printreg arg.(2)
  | Inegmulf ->
      fprintf ppf "-f (%a *f %a)"
        printreg arg.(0)
        printreg arg.(1)
  | Imuladdf ->
      fprintf ppf "%a +f (%a *f %a)"
        printreg arg.(0)
        printreg arg.(1)
        printreg arg.(2)
  | Inegmuladdf ->
      fprintf ppf "%a -f (%a *f %a)"
        printreg arg.(0)
        printreg arg.(1)
        printreg arg.(2)
  | Imulsubf ->
      fprintf ppf "(-f %a) +f (%a *f %a)"
        printreg arg.(0)
        printreg arg.(1)
        printreg arg.(2)
  | Inegmulsubf ->
      fprintf ppf "(-f %a) -f (%a *f %a)"
        printreg arg.(0)
        printreg arg.(1)
        printreg arg.(2)
  | Isqrtf ->
      fprintf ppf "sqrtf %a"
        printreg arg.(0)
  | Ibswap n ->
      fprintf ppf "bswap%i %a" n
        printreg arg.(0)

(* Recognize immediate operands *)

(* Immediate operands are 8-bit immediate values, zero-extended,
   and rotated right by 0 ... 30 bits.
   In Thumb/Thumb-2 mode we utilize 26 ... 30. *)

let is_immediate n =
  let n = ref n in
  let s = ref 0 in
  let m = if !thumb then 24 else 30 in
  while (!s <= m && Int32.logand !n 0xffl <> !n) do
    n := Int32.logor (Int32.shift_right_logical !n 2) (Int32.shift_left !n 30);
    s := !s + 2
  done;
  !s <= m
