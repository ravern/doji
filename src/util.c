
#define __doji_util_c

#include "util.h"

/* ---------------- */

uint8_t alignof(size_t size) {
  --size;
  uint8_t align = 0;
  while (size > 0) {
    size >>= 1;
    ++align;
  }
  return align;
}