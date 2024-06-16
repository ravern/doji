#ifndef __doji_parse_h
#define __doji_parse_h

#include "../include/doji.h"

#include "alloc.h"
#include "ast.h"
#include "lex.h"

/* ---------------- */

typedef struct Parser {
  Lexer       lex;
  Tok         cur_tok;
  Allocator*  alc;
  doji_Error* err;
} Parser;

void        prs_init(Parser*, Allocator*, char const* path, char const* src);
void        prs_destroy(Parser*);
doji_Error* prs_err(Parser const*);
Ast*        prs_parse(Parser*);

/* ---------------- */

#endif