#define __doji_vector_c

#include "vector.h"

#include "alloc.h"
#include "util.h"

/* ---------------- */

#define DOJI_VEC_DEFAULT_INIT_CAP 4
#define DOJI_VEC_GROW_FACTOR      2

/* ---------------- */

static size_t offset_from_align(size_t idx, uint8_t align) {
  return idx << align;
}

static size_t size_from_align(uint8_t align) {
  return offset_from_align(1, align);
}

/* ---------------- */

void vec_init(Vector* vec, Allocator const* alc, size_t init_cap, size_t item_size) {
  size_t actual_init_cap = init_cap != 0 ? init_cap : DOJI_VEC_DEFAULT_INIT_CAP;

  *vec = (Vector){
    .len = 0,
    .cap = actual_init_cap,
    .align = alignof(item_size),
    .alc = alc,
    .data = alc_alloc(alc, actual_init_cap * size_from_align(alignof(item_size))),
  };
}

void vec_destroy(Vector* vec) {
  alc_free(vec->alc, vec->data);
}

size_t vec_len(Vector const* vec) {
  return vec->len;
}

static void* vec_get_unchecked(Vector const* vec, size_t idx) {
  return vec->data + offset_from_align(idx, vec->align);
}

void const* vec_get(Vector const* vec, size_t idx) {
  if (idx >= vec->len) {
    return NULL;
  }
  return vec_get_unchecked(vec, idx);
}

static void* vec_set_unchecked(Vector* vec, size_t idx, void const* item) {
  void* new_item = vec_get_unchecked(vec, idx);
  memcpy(new_item, item, size_from_align(vec->align));
  return new_item;
}

void const* vec_set(Vector* vec, size_t idx, void const* item) {
  if (idx >= vec->len) {
    return NULL;
  }
  return vec_set_unchecked(vec, idx, item);
}

void const* vec_push(Vector* vec, void const* item) {
  if (vec->len == vec->cap) {
    vec_reserve(vec, vec->cap * DOJI_VEC_GROW_FACTOR);
  }
  return vec_set_unchecked(vec, vec->len++, item);
}

void vec_reserve(Vector* vec, size_t new_cap) {
  if (new_cap < vec->cap) {
    return;
  }
  vec->data = alc_realloc(vec->alc, vec->data, new_cap * size_from_align(vec->align));
  vec->cap = new_cap;
}

void vec_clear(Vector* vec) {
  vec->len = 0;
}