/*
   Kprl: RealLive compressor.
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
*/

#include "lzcomp.h"
extern "C" {
#include "rldev.h"

/* RealLive uses a rather basic XOR encryption scheme, to which this is the key. */
static uchar xor_mask[] = {
  0x8b, 0xe5, 0x5d, 0xc3, 0xa1, 0xe0, 0x30, 0x44, 0x00, 0x85, 0xc0, 0x74, 0x09, 0x5f, 0x5e, 0x33,
  0xc0, 0x5b, 0x8b, 0xe5, 0x5d, 0xc3, 0x8b, 0x45, 0x0c, 0x85, 0xc0, 0x75, 0x14, 0x8b, 0x55, 0xec,
  0x83, 0xc2, 0x20, 0x52, 0x6a, 0x00, 0xe8, 0xf5, 0x28, 0x01, 0x00, 0x83, 0xc4, 0x08, 0x89, 0x45,
  0x0c, 0x8b, 0x45, 0xe4, 0x6a, 0x00, 0x6a, 0x00, 0x50, 0x53, 0xff, 0x15, 0x34, 0xb1, 0x43, 0x00,
  0x8b, 0x45, 0x10, 0x85, 0xc0, 0x74, 0x05, 0x8b, 0x4d, 0xec, 0x89, 0x08, 0x8a, 0x45, 0xf0, 0x84,
  0xc0, 0x75, 0x78, 0xa1, 0xe0, 0x30, 0x44, 0x00, 0x8b, 0x7d, 0xe8, 0x8b, 0x75, 0x0c, 0x85, 0xc0,
  0x75, 0x44, 0x8b, 0x1d, 0xd0, 0xb0, 0x43, 0x00, 0x85, 0xff, 0x76, 0x37, 0x81, 0xff, 0x00, 0x00,
  0x04, 0x00, 0x6a, 0x00, 0x76, 0x43, 0x8b, 0x45, 0xf8, 0x8d, 0x55, 0xfc, 0x52, 0x68, 0x00, 0x00,
  0x04, 0x00, 0x56, 0x50, 0xff, 0x15, 0x2c, 0xb1, 0x43, 0x00, 0x6a, 0x05, 0xff, 0xd3, 0xa1, 0xe0,
  0x30, 0x44, 0x00, 0x81, 0xef, 0x00, 0x00, 0x04, 0x00, 0x81, 0xc6, 0x00, 0x00, 0x04, 0x00, 0x85,
  0xc0, 0x74, 0xc5, 0x8b, 0x5d, 0xf8, 0x53, 0xe8, 0xf4, 0xfb, 0xff, 0xff, 0x8b, 0x45, 0x0c, 0x83,
  0xc4, 0x04, 0x5f, 0x5e, 0x5b, 0x8b, 0xe5, 0x5d, 0xc3, 0x8b, 0x55, 0xf8, 0x8d, 0x4d, 0xfc, 0x51,
  0x57, 0x56, 0x52, 0xff, 0x15, 0x2c, 0xb1, 0x43, 0x00, 0xeb, 0xd8, 0x8b, 0x45, 0xe8, 0x83, 0xc0,
  0x20, 0x50, 0x6a, 0x00, 0xe8, 0x47, 0x28, 0x01, 0x00, 0x8b, 0x7d, 0xe8, 0x89, 0x45, 0xf4, 0x8b,
  0xf0, 0xa1, 0xe0, 0x30, 0x44, 0x00, 0x83, 0xc4, 0x08, 0x85, 0xc0, 0x75, 0x56, 0x8b, 0x1d, 0xd0,
  0xb0, 0x43, 0x00, 0x85, 0xff, 0x76, 0x49, 0x81, 0xff, 0x00, 0x00, 0x04, 0x00, 0x6a, 0x00, 0x76
};

/* Decrypt an "encrypted" file */
value rl_prim_apply_mask (value array, value origin)
{
  uchar i = 0;
  uchar *start = Binarray_val(array) + Long_val(origin);
  uchar *end = Binarray_val(array) + Bigarray_val(array)->dim[0];
  while (start < end) *start++ ^= xor_mask[i++];
  return Val_unit;
}

/* Decompress an archived file. */
value rl_prim_decompress (value src_in, value dst_in)
{
  int bit = 1;
  uchar *src = Binarray_val(src_in);
  uchar *dststart = Binarray_val(dst_in);
  uchar *dst = dststart;
  uchar *dstend = dststart + Bigarray_val(dst_in)->dim[0];
  uchar *srcend = src + Bigarray_val(src_in)->dim[0];
  uchar flag;
  src += 8;
  flag = *src++;
  while (src < srcend && dst < dstend) {
    if (bit == 256) {
      bit = 1;
      flag = *src++;
    }
    if (flag & bit)
      *dst++ = *src++;
    else {
      int i, count;
      uchar *repeat;
      count = *src++;
      count += (*src++) << 8;
      repeat = dst - ((count >> 4) - 1) - 1;
      count = (count & 0x0f) + 2;
      if (repeat < dststart || repeat >= dst)
        failwith ("corrupt data");
      for (i = 0; i < count; i++)
        *dst++ = *repeat++;
    }
    bit <<= 1;
  }
  return Val_unit;
}

value rl_prim_compress (value arr)
{
  AVG32Comp::Compress<AVG32Comp::CInfoRealLive, AVG32Comp::Container::RLDataContainer> cmp;
  char *data = (char*) Data_bigarray_val(arr);
  cmp.WriteData (data, Bigarray_val(arr)->dim[0]);
  cmp.WriteDataEnd();
  cmp.Deflate();
  cmp.Flush();
  memmove (data, cmp.Data(), cmp.Length());
  return Val_long(cmp.Length());
}

}
