(*
   Kprl: bytecode file header routines
   Copyright (C) 2006 Haeleth
   Revised 2009-2011 by Richard 23

   This program is free software; you can redistribute it and/or modify it under
   the terms of the GNU General Public License as published by the Free Software
   Foundation; either version 2 of the License, or (at your option) any later
   version.

   This program is distributed in the hope that it will be useful, but WITHOUT
   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
   FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
   details.

   You should have received a copy of the GNU General Public License along with
   this program; if not, write to the Free Software Foundation, Inc., 59 Temple
   Place - Suite 330, Boston, MA  02111-1307, USA.
*)

open Binarray

let archive = ref false

(* Header of a bytecode file. *)

type file_header_t =
  { header_version: int;
    compiler_version: int;
    data_offset: int;
    uncompressed_size: int;
    compressed_size: int option;
    int_0x2c: int;
    entry_points: int array;
    kidoku_lnums: int32 array;
    dramatis_personae: string list;
    rldev_metadata: Metadata.t; 
    archived: bool }

let empty_header =
  { header_version = 0;
    compiler_version = 0;
    data_offset = 0;
    uncompressed_size = 0;
    compressed_size = None;
    int_0x2c = 0;
    entry_points = [||];
    kidoku_lnums = [||];
    dramatis_personae = [];
    rldev_metadata = Metadata.empty; 
    archived = !archive }

(* Bytecode files don't have a convenient TPC32 identifier in their header 
   like in AVG32, so we have to test files by checking for known data. *)
   
let is_bytecode arr idx =
  let id = read arr idx 4 in
  
(*
  Optpp.sysInfo (Printf.sprintf "pos: %d; id: %08x" idx (get_int arr idx));
*)
  
  List.mem id ["RDRL"; "RD2K"; "RDRM"]
  || List.mem id ["KPRL"; "KP2K"; "KPRM"; 
        "\xd0\x01\x00\x00"; 
        "\xcc\x01\x00\x00"; 
        "\xb8\x01\x00\x00"]
     && List.mem (get_int arr (idx + 4)) [
        10002; (* Most games *)
        110002; (* Little Busters! *)
        1110002 (* Little Busters! EX *)]

let uncompressed_header s =
  List.mem s [
          "KPRL"; (* RealLive, compiler 10002 *)
          "KP2K"; (* AVG2000 *)
          "KPRM"; (* RealLive, compiler 110002 *)
          "RDRL"; (* As KPRL, but following 4 bytes are version no *)
          "RD2K"; (* As KP2K, but following 4 bytes are version no *)
          "RDRM"] (* As KPRM, but following 4 bytes are version no *)

(* Read a file_header_t structure.  The arr parameter should be a 
   complete bytecode file: when reading an archive, pass the t 
   returned by get_subfile. *)
   
let read_file_header ?(rd_handler = (fun _ -> ())) arr =
(*
  Optpp.sysInfo "read_file_header ()";
*)
  
  if not (is_bytecode arr 0) then failwith "not a bytecode file";
  let cversion =
    if read arr 0 2 = "RD" then begin
      rd_handler arr;
      if read arr 2 2 = "RM"
      then 110002
      else 10002
    end
    else get_int arr 4
  in
  
(*
  ignore (Printf.printf "archive: %s\n" (if !archive then "true" else "false"));
*)

(*
  Optpp.sysInfo (Printf.sprintf "archive: %s" (if !archive then "true" else "false"));
*)

  match read arr 0 4 with
    | "KP2K" | "RD2K"
    | "\xcc\x01\x00\x00"
     -> { empty_header with
          header_version = 1;
          compiler_version  = cversion;
          data_offset       = 0x1cc + get_int arr 0x20 * 4;
          uncompressed_size = get_int arr 0x24;
          int_0x2c          = get_int arr 0x28;
          archived            = !archive }
    | "KPRL" | "RDRL" | "KPRM" | "RDRM"
    | "\xd0\x01\x00\x00"
     -> { empty_header with
          header_version = 2;
          compiler_version  = cversion;
          data_offset       = get_int arr 0x20;
          uncompressed_size = get_int arr 0x24;
          compressed_size   = Some (get_int arr 0x28);
          int_0x2c          = get_int arr 0x2c; 
          archived            = !archive }
    | _ -> failwith "unsupported header format"

let read_full_header ?(rd_handler = (fun _ -> ())) arr =
(*
  Optpp.sysInfo "read_full_header ()";
*)
  
  let hdr = read_file_header arr ~rd_handler in
  match hdr.header_version with
    | 1 -> { hdr with
             entry_points =
               Array.init 100 (fun i -> get_int arr (0x30 + i * 4));
             kidoku_lnums =
               Array.init (get_int arr 0x20)
                (fun i ->
                   get_int32 arr (0x1cc + i * 4)); }

    | 2 -> { hdr with
             entry_points =
               Array.init 100 (fun i -> get_int arr (0x34 + i * 4));
             kidoku_lnums =
              (let t1_offset = get_int arr 0x08 in
               Array.init (get_int arr 0x0c)
                 (fun i ->
                   get_int32 arr (t1_offset + i * 4)));
             dramatis_personae =
              (let offset = ref (get_int arr 0x14) in
               ExtList.List.init (get_int arr 0x18)
                 (fun _ ->
                   let idx = !offset + 4
                   and len = get_int arr !offset in
                   offset := idx + len;
                   read_sz arr ~idx ~len));
             rldev_metadata =
              (let dp_end = get_int arr 0x14 + get_int arr 0x1c in
               if dp_end == hdr.data_offset
               then hdr.rldev_metadata
               else Metadata.read arr dp_end); }

    | _ -> assert false
