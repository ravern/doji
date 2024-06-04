#ifndef __doji_gc_h
#define __doji_gc_h

#include "../include/doji.h"

#include "alloc.h"

/* ---------------- */

typedef enum GcObjectType {
  GC_OBJECT_STRING,
  GC_OBJECT_LIST,
  GC_OBJECT_MAP,
  GC_OBJECT_FIBER,
} GcObjectType;

typedef struct GcObject GcObject;
struct GcObject {
  bool         is_mark;
  GcObjectType type;
  GcObject*    next;
};

/* ---------------- */

typedef struct GcState {
  Allocator const* alc;
  Allocator        gc_alc;
  doji_Fiber*      root;
  GcObject*        objs;
} GcState;

void             gc_init(GcState*, Allocator const*);
void             gc_destroy(GcState*);
void             gc_set_root(GcState*, doji_Fiber*);
Allocator const* gc_alc(GcState*);
void             gc_collect(GcState*);

/* ---------------- */

#endif