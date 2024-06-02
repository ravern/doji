#include "alloc.h"
#define __doji_vector_c

#include "vector.h"

#include "util.h"

/* ---------------- */

static size_t offset_from_align(size_t idx, uint8_t align) {
  return idx << align;
}

static size_t size_from_align(uint8_t align) {
  return offset_from_align(1, align);
}

void vec_init(Vector* vec, Allocator* alc, size_t init_cap, size_t item_size) {
  vec->len = 0;
  vec->cap = init_cap;
  vec->align = alignof(item_size);
  vec->alc = alc;
  vec->data = malloc(init_cap * size_from_align(vec->align));
}

size_t vec_len(Vector* vec) {
  return vec->len;
}

static void* vec_get_unchecked(Vector* vec, size_t idx) {
  return vec->data + offset_from_align(idx, vec->align);
}

void* vec_get(Vector* vec, size_t idx) {
  assert(idx < vec->len);
  return vec_get_unchecked(vec, idx);
}

static void* vec_set_unchecked(Vector* vec, size_t idx, const void* item) {
  void* new_item = vec_get_unchecked(vec, idx);
  memcpy(new_item, item, size_from_align(vec->align));
  return new_item;
}

void* vec_set(Vector* vec, size_t idx, const void* item) {
  assert(idx < vec->len);
  return vec_set_unchecked(vec, idx, item);
}

void* vec_push(Vector* vec, const void* item) {
  if (vec->len == vec->cap) {
    vec_reserve(vec, vec->cap * 2);
  }
  return vec_set_unchecked(vec, vec->len++, item);
}

void vec_reserve(Vector* vec, size_t new_cap) {
  assert(new_cap < vec->cap);
  vec->data = realloc(vec->data, new_cap * size_from_align(vec->align));
  vec->cap = new_cap;
}