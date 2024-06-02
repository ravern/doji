#define __doji_alloc_c

#include "alloc.h"

/* ---------------- */

void* alc_alloc(Allocator* alc, size_t size) {
  void* data = alc->alloc(size);
  if (data == NULL) {
    longjmp(alc->err, 1);
  }
  return data;
}

void* alc_realloc(Allocator* alc, void* data, size_t size) {
  void* new_data = alc->realloc(data, size);
  if (new_data == NULL) {
    alc_free(alc, data);
    longjmp(alc->err, 1);
  }
  return new_data;
}

void alc_free(Allocator* alc, void* data) {
  return alc->free(data);
}