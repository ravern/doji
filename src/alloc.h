#ifndef __doji_alloc_h
#define __doji_alloc_h

#include "../include/doji.h"

/* ---------------- */

typedef void* (*AllocFn)(void* state, size_t);
typedef void* (*ReallocFn)(void* state, void*, size_t);
typedef void (*FreeFn)(void* state, void*);

typedef struct Allocator {
  void*     state;
  jmp_buf*  err_buf;
  AllocFn   alloc;
  ReallocFn realloc;
  FreeFn    free;
} Allocator;

void  alc_init(Allocator*, void* state, jmp_buf* err_buf, AllocFn, ReallocFn, FreeFn);
void* alc_alloc(Allocator*, size_t);
void* alc_realloc(Allocator*, void*, size_t);
void  alc_free(Allocator*, void*);

/* ---------------- */

#endif