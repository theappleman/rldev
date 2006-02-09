(*
    RLdev: transformations of Unicode to the CP932 codespace
    Copyright (C) 2006 Haeleth

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

open ExtString
open Printf
open Encoding
open Text

(* Encode Simplified Chinese text.
   Fail on characters that cannot be represented in the GBK encoding. *)
let encode_kfc fail text =
  let b = Buffer.create 0 in
  Text.iter
    (fun ch ->
      let gbch = 
        if ch <= 0x7f 
        then ch 
        else try
          IMap.find ch Cp936.map.uni_to_db 
        with Not_found ->
          fail ch; assert false
      in
      assert (gbch >= 0 && gbch <= 0xf7fe);
      if gbch < 0x80 then
        Buffer.add_char b (char_of_int gbch)
      else 
        match gbch with
        (* Special cases: 
            1. Characters we want to encode directly as their CP932 equivalents;
            2. Characters this would collide with, which we encode in the place of other, non-existent characters *)
          | 0xa1b8 -> Buffer.add_string b "\x81\x75" | 0xbba2 -> Buffer.add_string b "\x81\x53"
          | 0xa1ba -> Buffer.add_string b "\x81\x77" | 0xdda2 -> Buffer.add_string b "\x82\x52"
          | 0xa3a8 -> Buffer.add_string b "\x81\x69" | 0xb5a2 -> Buffer.add_string b "\x82\x53"
      
        (* General case *)
          | _ -> let c1 = (gbch lsr 8) land 0xff - 0xa1
                 and c2 = gbch land 0xff - 0xa1 in
                 assert (c1 >= 0 && c2 >= 0);
                 let c1 = c1 * 2 + (c2 mod 2) + 0x40
                 and c2 = c2 / 2 + 0x81 in
                 let c1 = if c1 >= 0x7f then c1 + 1 else c1
                 and c2 = if c2 > 0x9f then c2 + 0x40 else c2 in
                 Buffer.add_char b (char_of_int c2);
                 Buffer.add_char b (char_of_int c1))
    text;
  Buffer.contents b

(* The inverse. *)
let decode_kfc text =
  let b = Buf.create 0 in
  let rec getc idx =
    if idx = String.length text then
      Buf.contents b
    else
      let c = text.[idx] in
      match c with
        | '\x81'..'\x9f' | '\xe0'..'\xef' | '\xf0'..'\xfc' when idx + 1 < String.length text
            -> let a1 = int_of_char c and a2 = int_of_char text.[idx + 1] in
               let c1, c2 =
                 match (a1 lsl 8) lor a2 with
                   | 0x8175 -> 0xa1 - 0xa1, 0xb8 - 0xa1
    	           | 0x8177 -> 0xa1 - 0xa1, 0xba - 0xa1
    	           | 0x8169 -> 0xa3 - 0xa1, 0xa8 - 0xa1
    	           | 0x8153 -> 0xbb - 0xa1, 0xa2 - 0xa1
    	           | 0x8252 -> 0xdd - 0xa1, 0xa2 - 0xa1
    	           | 0x8253 -> 0xb5 - 0xa1, 0xa2 - 0xa1
                   | _ -> let c2 = ((if a1 > 0xdf then a1 - 0x40 else a1) - 0x81) * 2
                          and c1 = (if a2 >= 0x80 then a2 - 1 else a2) - 0x40 in
                          c1 / 2, c2 + (c1 mod 2)
               in
               Buf.add_int b Cp936.map.db_to_uni.(c1).(c2);
               getc (idx + 2)
        | '\x00'..'\x7f' -> Buf.add_char b c; getc (idx + 1)
        | _ -> failwith "malformed string"
  in
  getc 0

(* As above, but for Western text *)
let encode_cp1252 fail text =
  let b = Buffer.create 0 in
  Text.iter
    (fun ch ->
      if ch >= 0x1ff00 && ch < 0x20000 then
        (* Special case for encoding name variables and exfont moji. *)
        Buffer.add_string b (IMap.find (ch - 0x10000) Cp932.uni_to_db)
      else
        let wc = 
          match ch with
            | 0x20ac -> 0x80 | 0x201a -> 0x82 | 0x0192 -> 0x83 | 0x201e -> 0x84
            | 0x2026 -> 0x85 | 0x2020 -> 0x86 | 0x2021 -> 0x87 | 0x02c6 -> 0x88 
            | 0x2030 -> 0x89 | 0x0160 -> 0x8a | 0x2039 -> 0x8b | 0x0152 -> 0x8c 
            | 0x017d -> 0x8e | 0x2018 -> 0x91 | 0x2019 -> 0x92 | 0x201c -> 0x93 
            | 0x201d -> 0x94 | 0x2022 -> 0x95 | 0x2013 -> 0x96 | 0x2014 -> 0x97 
            | 0x02dc -> 0x98 | 0x2122 -> 0x99 | 0x0161 -> 0x9a | 0x203a -> 0x9b 
            | 0x0153 -> 0x9c | 0x017e -> 0x9e | 0x0178 -> 0x9f | _      -> ch
        in
        if wc < 0 || wc > 0xff then fail ch;
        let c = char_of_int wc in
        match c with
          | '\x00' .. '\x7f' -> Buffer.add_char b c
          | '\x80' .. '\xbf' -> Buffer.add_char b '\x89'; Buffer.add_char b c
          | '\xc0' .. '\xfe' -> Buffer.add_char b (char_of_int (wc - 0x1f))
          | '\xff'           -> Buffer.add_string b "\x89\xc0")
    text;
  Buffer.contents b

let decode_cp1252 text =
  let b = Buf.create 0 in
  if String.fold_left
       (fun b1 ch ->
          if b1 then ((
            match ch with
              | '\x80' .. '\xbf' 
                 -> Buf.add_int b 
                      (match int_of_char ch with 
                         | 0x80 -> 0x20ac | 0x82 -> 0x201a | 0x83 -> 0x0192 | 0x84 -> 0x201e 
                         | 0x85 -> 0x2026 | 0x86 -> 0x2020 | 0x87 -> 0x2021 | 0x88 -> 0x02c6 
                         | 0x89 -> 0x2030 | 0x8a -> 0x0160 | 0x8b -> 0x2039 | 0x8c -> 0x0152 
                         | 0x8e -> 0x017d | 0x91 -> 0x2018 | 0x92 -> 0x2019 | 0x93 -> 0x201c 
                         | 0x94 -> 0x201d | 0x95 -> 0x2022 | 0x96 -> 0x2013 | 0x97 -> 0x2014 
                         | 0x98 -> 0x02dc | 0x99 -> 0x2122 | 0x9a -> 0x0161 | 0x9b -> 0x203a 
                         | 0x9c -> 0x0153 | 0x9e -> 0x017e | 0x9f -> 0x0178 | c    -> c)
              | '\xc0' -> Buf.add_char b '\xff'
              | _ -> failwith "malformed string"
            ); false)
          else match ch with
            | '\x00' .. '\x7f' -> Buf.add_char b ch; false
            | '\x89' -> true
            | '\xa1' .. '\xdf' -> Buf.add_int b (int_of_char ch + 0x1f); false
            | _ -> failwith "malformed string")
       false text
  then failwith "malformed string"
  else Buf.contents b


(* Output transformations *)
let outenc = ref `None

let describe () =
  match !outenc with
    | `None -> "no output transformation"
    | `Chinese -> "the `Chinese' transformation of GB2312"
    | `Western -> "the `Western' transformation of CP1252"

(* Encode text according to a given Unicode -> CP932-codespace transformation *)
let make_cp932_compatible fail text =
  match !outenc with
    | `Chinese -> encode_kfc fail text
    | `Western -> encode_cp1252 fail text
    | `None -> assert false

(* Decode text again *)
let read_cp932_compatible fail text =
  try match !outenc with
    | `None -> Text.of_sjs text
    | `Chinese -> decode_kfc text
    | `Western -> decode_cp1252 text
  with Failure s ->
    fail s;
    Text.empty

(* Try to load a supported transformation corresponding to an input string *)
let init =
  let loaded_936 = ref false in
  function
    | `None -> outenc := `None
    | `Western -> outenc := `Western
    | `Chinese -> outenc := `Chinese; if not !loaded_936 then (loaded_936 := true; Cp936.init ())

let set_encoding enc =
  match String.uppercase enc with
    | "" | "NONE" | "JAPANESE" | "JP" | "CP932" | "SHIFT_JIS" | "SJIS" | "SHIFT-JIS" | "SHIFTJIS" -> init `None
    | "CHINESE" | "ZH" | "CN" | "CP936" | "GB2312" | "GBK" -> init `Chinese
    | "WESTERN" | "ENGLISH" | "EN" | "CP1252" -> init `Western
    | _ -> ksprintf failwith "unknown output transformation `%s'" enc

(* Convert a string to the format required for RealLive bytecode *)
let to_sjs_bytecode a =
  let b = Buffer.create 0 in
  Text.iter
    (fun c ->
      try
        Buffer.add_string b (IMap.find c Cp932.uni_to_db)
      with Not_found ->
        raise (Text.Bad_char c))
    a;
  Buffer.contents b

let to_bytecode a =
  match !outenc with
    | `None -> to_sjs_bytecode a
    | enc -> make_cp932_compatible (fun c -> raise (Text.Bad_char c)) a
