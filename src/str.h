#ifndef __doji_str_h
#define __doji_str_h

#include "../include/doji.h"

#include "alloc.h"
#include "vector.h"

/* ---------------- */

typedef struct StrBuilder {
  Vector str;
} StrBuilder;

void  strb_init(StrBuilder*, Allocator*, size_t init_cap);
void  strb_destroy(StrBuilder*);
void  strb_push(StrBuilder*, char);
void  strb_push_str(StrBuilder*, char const*);
void  strb_push_size(StrBuilder*, size_t);
void  strb_indent(StrBuilder*, size_t);
char* strb_build(StrBuilder*);

#endif