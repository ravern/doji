#define __doji_gc_c

#include "gc.h"

/* ---------------- */

void gc_init(GcState* gc, Allocator* alc) {
  *gc = (GcState){
    .alc = alc,
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

void gc_set_root(GcState* gc, doji_Fiber* root) {
  gc->root = root;
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