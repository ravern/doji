
#include "alloc.h"
#define __doji_error_c

#include "error.h"

/* ---------------- */

void loc_display(Loc loc, StrBuilder* strb) {
  strb_push_str(strb, loc.path);
  strb_push(strb, ':');
  strb_push_size(strb, loc.line);
  strb_push(strb, ':');
  strb_push_size(strb, loc.col);
}

char const* loc_str(Loc loc, Allocator* alc) {
  StrBuilder strb;
  strb_init(&strb, alc, 0);
  loc_display(loc, &strb);
  return strb_build(&strb);
}

/* ---------------- */

void err_init(doji_Error* err, Allocator* alc, Loc loc, char* msg) {
  *err = (doji_Error){
    .loc = loc,
    .msg = msg,
  };
}

void err_destroy(doji_Error* err) {
  alc_free(err->alc, err->msg);
}

void err_display(doji_Error const* err, StrBuilder* strb) {
  loc_display(err->loc, strb);
  strb_push_str(strb, ": ");
  strb_push_str(strb, err->msg);
}

char const* err_str(doji_Error const* err, Allocator* alc) {
  StrBuilder strb;
  strb_init(&strb, alc, 0);
  err_display(err, &strb);
  return strb_build(&strb);
}