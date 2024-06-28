#define __doji_alloc_c

#include "alloc.h"

/* ---------------- */

Allocator alc_new(void* state, jmp_buf* err_buf, AllocFn alloc, ReallocFn realloc, FreeFn free) {
  Allocator alc;
  alc.err_buf = err_buf;
  alc.state = state;
  alc.alloc = alloc;
  alc.realloc = realloc;
  alc.free = free;
  return alc;
}

void* alc_alloc(Allocator* alc, size_t size) {
  void* data = alc->alloc(alc->state, size);
  if (!data) {
    longjmp(*alc->err_buf, 1);
  }
  return data;
}

void* alc_realloc(Allocator* alc, void* data, size_t size) {
  void* new_data = alc->realloc(alc->state, data, size);
  if (!new_data) {
    alc_free(alc, data);
    longjmp(*alc->err_buf, 1);
  }
  return new_data;
}

void alc_free(Allocator* alc, void* data) {
  return alc->free(alc->state, data);
}