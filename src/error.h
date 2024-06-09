#ifndef __doji_error_h
#define __doji_error_h

#include "../include/doji.h"

#include "str.h"

/* ---------------- */

typedef struct Loc {
  char const* path;
  size_t      line;
  size_t      col;
} Loc;

void        loc_display(Loc, StrBuilder*);
char const* loc_str(Loc, Allocator*);

/* ---------------- */

struct doji_Error {
  Loc        loc;
  char*      msg;
  Allocator* alc;
};

void        err_init(doji_Error*, Allocator*, Loc, char* msg);
void        err_destroy(doji_Error*);
void        err_display(doji_Error const*, StrBuilder*);
char const* err_str(doji_Error const*, Allocator*);

#endif