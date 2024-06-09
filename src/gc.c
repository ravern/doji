#define __doji_gc_c

#include "gc.h"

#include "alloc.h"

/* ---------------- */

void* gc_alc_alloc(void* state, size_t size) {
  GcState* gc = state;
  return gc->alc->alloc(gc->alc->state, size);
}

void* gc_alc_realloc(void* state, void* data, size_t size) {
  GcState* gc = state;
  return gc->alc->realloc(gc->alc->state, data, size);
}

void gc_alc_free(void* state, void* data) {
  GcState* gc = state;
  gc->alc->free(gc->alc->state, data);
}

/* ---------------- */

void gc_init(GcState* gc, Allocator* alc) {
  Allocator gc_alc;
  alc_init(&gc_alc, gc, alc->err_buf, gc_alc_alloc, gc_alc_realloc, gc_alc_free);
  *gc = (GcState){
    .alc = alc,
    .gc_alc = gc_alc,
    .root = NULL,
    .objs = NULL,
  };
}

void gc_destroy(GcState* gc) {
  GcObject* obj = gc->objs;
  while (obj) {
    GcObject* next = obj->next;
    alc_free(gc->alc, obj);
    obj = next;
  }
}

void gc_set_root(GcState* gc, Fiber* root) {
  gc->root = root;
}

Allocator* gc_alc(GcState* gc) {
  return &gc->gc_alc;
}

GcObject* gc_alloc(GcState* gc, size_t size) {
  GcObject* obj = alc_alloc(gc->alc, size);
  *obj = (GcObject){
    .is_mark = false,
    .type = 0,
    .next = gc->objs,
  };
  gc->objs = obj;
  return obj;
}