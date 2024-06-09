#define __doji_alloc_c

#include "alloc.h"

/* ---------------- */

void alc_init(
    Allocator* alc, void* state, jmp_buf* err_buf, AllocFn alloc, ReallocFn realloc, FreeFn free) {
  *alc = (Allocator){
    .err_buf = err_buf,
    .state = state,
    .alloc = alloc,
    .realloc = realloc,
    .free = free,
  };
}

void* alc_alloc(Allocator const* alc, size_t size) {
  void* data = alc->alloc(alc->state, size);
  if (!data) {
    longjmp(*alc->err_buf, 1);
  }
  return data;
}

void* alc_realloc(Allocator const* alc, void* data, size_t size) {
  void* new_data = alc->realloc(alc->state, data, size);
  if (!new_data) {
    alc_free(alc, data);
    longjmp(*alc->err_buf, 1);
  }
  return new_data;
}

void alc_free(Allocator const* alc, void* data) {
  return alc->free(alc->state, data);
}