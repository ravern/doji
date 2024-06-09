#ifndef __doji_lex_h
#define __doji_lex_h

#include "../include/doji.h"

#include "alloc.h"
#include "ast.h"
#include "error.h"

/* ---------------- */

typedef enum TokType {
  /* Literals */
  TOK_INT,
  TOK_FLOAT,
  TOK_IDENT,
  /* Keywords */
  TOK_NIL,
  TOK_TRUE,
  TOK_FALSE,
  TOK_FN,
  TOK_IF,
  TOK_FOR,
  TOK_WHILE,
  /* Puncutation */
  TOK_L_PAREN,
  TOK_R_PAREN,
  TOK_L_BRACE,
  TOK_R_BRACE,
  TOK_L_BRACKET,
  TOK_R_BRACKET,
  TOK_SEMICOLON,
  TOK_COLON,
  TOK_PERIOD,
  TOK_COMMA,
  TOK_PLUS,
  TOK_PLUS_EQ,
  TOK_HYPHEN,
  TOK_HYPHEN_EQ,
  TOK_STAR,
  TOK_STAR_EQ,
  TOK_SLASH,
  TOK_SLASH_EQ,
  TOK_PERCENT,
  TOK_PERCENT_EQ,
  TOK_EQ,
  TOK_EQ_EQ,
  TOK_GT,
  TOK_GT_EQ,
  TOK_LT,
  TOK_LT_EQ,
  TOK_BANG,
  TOK_BANG_EQ,
  TOK_AND,
  TOK_OR,
  TOK_BAND,
  TOK_BOR,
  TOK_BNOT,
  /* Miscellaneous */
  TOK_EOF,
} TokType;

void        tok_type_display(TokType, StrBuilder*);
char const* tok_type_str(TokType, Allocator*);

typedef struct Tok {
  Span    span;
  TokType type;
} Tok;

/* ---------------- */

typedef struct Lexer {
  char const* src;
  Loc         cur_loc;
  Span        cur_span;
  Allocator*  alc;
  doji_Error* err;
} Lexer;

void              lex_init(Lexer*, Allocator*, char const* path, char const* src);
void              lex_destroy(Lexer*);
Tok               lex_next(Lexer*);
doji_Error const* lex_err(Lexer const*);

#endif