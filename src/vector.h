#ifndef __doji_vector_h
#define __doji_vector_h

#include "../include/doji.h"

#include "alloc.h"

/* ---------------- */

typedef struct Vector {
  size_t           len;
  size_t           cap;
  uint8_t          align;
  Allocator const* alc;
  uint8_t*         data;
} Vector;

void        vec_init(Vector*, Allocator const*, size_t init_cap, size_t item_size);
void        vec_destroy(Vector*);
size_t      vec_len(Vector const*);
void const* vec_get(Vector const*, size_t idx);
void const* vec_set(Vector*, size_t idx, void const*);
void const* vec_push(Vector*, void const*);
void        vec_reserve(Vector*, size_t new_cap);
void        vec_clear(Vector*);

/* ---------------- */

#endif