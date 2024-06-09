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
char const* loc_str(Loc, Allocator const*);

/* ---------------- */

struct doji_Error {
  Loc         loc;
  char const* msg;
};

void        err_init(doji_Error*, Loc, char const* msg);
void        err_destroy(doji_Error*);
void        err_display(doji_Error const*, StrBuilder*);
char const* err_str(doji_Error const*, Allocator const*);

#endif