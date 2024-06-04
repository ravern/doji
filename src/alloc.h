#ifndef __doji_alloc_h
#define __doji_alloc_h

#include "../include/doji.h"

/* ---------------- */

typedef struct Allocator {
  jmp_buf* err_buf;
  void* (*alloc)(size_t);
  void* (*realloc)(void*, size_t);
  void (*free)(void*);
} Allocator;

void* alc_alloc(Allocator*, size_t);
void* alc_realloc(Allocator*, void*, size_t);
void  alc_free(Allocator*, void*);

/* ---------------- */

#endif