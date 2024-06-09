#include "ast.h"
#include "str.h"
#define __doji_lex_c

#include "lex.h"

/* ---------------- */

void tok_type_display(TokType type, StrBuilder* strb) {
  strb_push_str(strb, tok_type_str(type, NULL));
}

char const* tok_type_str(TokType type, Allocator* alc) {
  switch (type) {
  case TOK_INT:        return "int";
  case TOK_FLOAT:      return "float";
  case TOK_IDENT:      return "ident";
  case TOK_NIL:        return "nil";
  case TOK_TRUE:       return "true";
  case TOK_FALSE:      return "false";
  case TOK_FN:         return "fn";
  case TOK_IF:         return "if";
  case TOK_FOR:        return "for";
  case TOK_WHILE:      return "while";
  case TOK_L_PAREN:    return "(";
  case TOK_R_PAREN:    return ")";
  case TOK_L_BRACE:    return "{";
  case TOK_R_BRACE:    return "}";
  case TOK_L_BRACKET:  return "[";
  case TOK_R_BRACKET:  return "]";
  case TOK_SEMICOLON:  return ";";
  case TOK_COLON:      return ":";
  case TOK_PERIOD:     return ".";
  case TOK_COMMA:      return ",";
  case TOK_PLUS:       return "+";
  case TOK_PLUS_EQ:    return "+=";
  case TOK_HYPHEN:     return "-";
  case TOK_HYPHEN_EQ:  return "-=";
  case TOK_STAR:       return "*";
  case TOK_STAR_EQ:    return "*=";
  case TOK_SLASH:      return "/";
  case TOK_SLASH_EQ:   return "/=";
  case TOK_PERCENT:    return "%";
  case TOK_PERCENT_EQ: return "%=";
  case TOK_EQ:         return "=";
  case TOK_EQ_EQ:      return "==";
  case TOK_GT:         return ">";
  case TOK_GT_EQ:      return ">=";
  case TOK_LT:         return "<";
  case TOK_LT_EQ:      return "<=";
  case TOK_BANG:       return "!";
  case TOK_BANG_EQ:    return "!=";
  case TOK_AND:        return "&&";
  case TOK_OR:         return "||";
  case TOK_BAND:       return "&";
  case TOK_BOR:        return "|";
  case TOK_BNOT:       return "~";
  case TOK_EOF:        return "EOF";
  }
}

/* ---------------- */

static bool is_digit(char c) {
  return c >= '0' && c <= '9';
}

static bool is_alpha(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static bool is_alnum(char c) {
  return is_alpha(c) || is_digit(c);
}

static bool is_whitespace(char c) {
  return c == '\n' || c == '\r' || c == '\t' || c == ' ';
}

static bool is_newline(char c) {
  return c == '\n';
}

/* ---------------- */

void lex_init(Lexer* lex, Allocator* alc, char const* path, char const* src) {
  *lex = (Lexer){
    .src = src,
    .cur_loc = {.path = path, .line = 1, .col = 1},
    .cur_span = {.start = 0, .len = 0},
    .alc = alc,
    .err = NULL,
  };
}

void lex_destroy(Lexer* lex) {
  if (lex->err) {
    alc_free(lex->alc, lex->err);
  }
}

static void lex_init_err(Lexer* lex, char u, char const* e) {
  StrBuilder strb;
  strb_init(&strb, lex->alc, 0);
  strb_push_str(&strb, "unexpected char '");
  strb_push(&strb, u);
  strb_push_str(&strb, "', expected '");
  strb_push_str(&strb, e);
  strb_push(&strb, '\'');
  char* msg = strb_build(&strb);

  if (lex->err) {
    err_destroy(lex->err);
  }

  lex->err = alc_alloc(lex->alc, sizeof(doji_Error));
  err_init(lex->err, lex->alc, lex->cur_loc, msg);
}

static char lex_peek(Lexer const* lex) {
  return lex->src[lex->cur_span.start + lex->cur_span.len];
}

static char lex_advance(Lexer* lex) {
  char c = lex_peek(lex);
  ++lex->cur_span.len;
  ++lex->cur_loc.col;
  if (is_newline(c)) {
    ++lex->cur_loc.line;
    lex->cur_loc.col = 1;
  }
  return c;
}

static char lex_expect(Lexer* lex, char e) {
  char c = lex_advance(lex);
  if (c != e) {
    char e_str[2] = {e, '\0'};
    lex_init_err(lex, c, e_str);
    return '\0';
  }
  return c;
}

static Span lex_reset_span(Lexer* lex) {
  Span cur_span = lex->cur_span;
  lex->cur_span = (Span){
    .start = lex->cur_span.start + lex->cur_span.len,
    .len = 0,
  };
  return cur_span;
}

static void lex_skip_whitespace(Lexer* lex) {
  for (char c = lex_peek(lex); is_whitespace(c); c = lex_peek(lex)) {
    lex_advance(lex);
  }
  lex_reset_span(lex);
}

static Tok lex_build_tok(Lexer* lex, TokType type) {
  return (Tok){
    .span = lex_reset_span(lex),
    .type = type,
  };
}

static Tok lex_build_num_tok(Lexer* lex) {
  bool is_float = false;

  for (char c = lex_peek(lex); is_digit(c) || c == '.'; c = lex_peek(lex)) {
    lex_advance(lex);
    if (c == '.') {
      if (is_float) {
        lex_init_err(lex, c, "digit");
        return lex_build_tok(lex, TOK_EOF);
      } else {
        is_float = true;
        c = lex_peek(lex);
        if (!is_digit(c)) {
          lex_init_err(lex, c, "digit");
          return (Tok){0};
        }
      }
    }
  }

  return lex_build_tok(lex, is_float ? TOK_FLOAT : TOK_INT);
}

static Tok lex_build_ident_tok(Lexer* lex) {
  char c = lex_peek(lex);
  for (char c = lex_peek(lex); is_alnum(c) || c == '_'; c = lex_peek(lex)) {
    lex_advance(lex);
  }

  size_t start = lex->cur_span.start;
  size_t len = lex->cur_span.len;

#define DOJI_LEX_CHECK_KEYWORD(kw, t)                         \
  if (lex->cur_span.len == (sizeof(kw) - 1) / sizeof(char) && \
      strncmp(lex->src + start, kw, len) == 0) {              \
    return lex_build_tok(lex, t);                             \
  }

  DOJI_LEX_CHECK_KEYWORD("nil", TOK_NIL);
  DOJI_LEX_CHECK_KEYWORD("true", TOK_TRUE);
  DOJI_LEX_CHECK_KEYWORD("false", TOK_FALSE);
  DOJI_LEX_CHECK_KEYWORD("fn", TOK_FN);
  DOJI_LEX_CHECK_KEYWORD("if", TOK_IF);
  DOJI_LEX_CHECK_KEYWORD("for", TOK_FOR);
  DOJI_LEX_CHECK_KEYWORD("while", TOK_WHILE);
  return lex_build_tok(lex, TOK_IDENT);
}

Tok lex_next(Lexer* lex) {
  lex_skip_whitespace(lex);

  char c = lex_peek(lex);

#define DOJI_LEX_CASE_SINGLE(c, t) \
  case c: {                        \
    lex_advance(lex);              \
    return lex_build_tok(lex, t);  \
  }

#define DOJI_LEX_CASE_DOUBLE(c_1, c_2, t_1, t_2) \
  case c_1: {                                    \
    lex_advance(lex);                            \
    if (lex_peek(lex) == c_2) {                  \
      lex_advance(lex);                          \
      return lex_build_tok(lex, t_2);            \
    } else {                                     \
      return lex_build_tok(lex, t_1);            \
    }                                            \
  }

  switch (c) {
    DOJI_LEX_CASE_SINGLE('\0', TOK_EOF);
    DOJI_LEX_CASE_SINGLE('(', TOK_L_PAREN);
    DOJI_LEX_CASE_SINGLE(')', TOK_R_PAREN);
    DOJI_LEX_CASE_SINGLE('{', TOK_L_BRACE);
    DOJI_LEX_CASE_SINGLE('}', TOK_R_BRACE);
    DOJI_LEX_CASE_SINGLE('[', TOK_L_BRACKET);
    DOJI_LEX_CASE_SINGLE(']', TOK_R_BRACKET);
    DOJI_LEX_CASE_SINGLE(';', TOK_SEMICOLON);
    DOJI_LEX_CASE_SINGLE(':', TOK_COLON);
    DOJI_LEX_CASE_SINGLE('.', TOK_PERIOD);
    DOJI_LEX_CASE_SINGLE(',', TOK_COMMA);
    DOJI_LEX_CASE_DOUBLE('+', '=', TOK_PLUS, TOK_PLUS_EQ);
    DOJI_LEX_CASE_DOUBLE('-', '=', TOK_HYPHEN, TOK_HYPHEN_EQ);
    DOJI_LEX_CASE_DOUBLE('*', '=', TOK_STAR, TOK_STAR_EQ);
    DOJI_LEX_CASE_DOUBLE('/', '=', TOK_SLASH, TOK_SLASH_EQ);
    DOJI_LEX_CASE_DOUBLE('%', '=', TOK_PERCENT, TOK_PERCENT_EQ);
    DOJI_LEX_CASE_DOUBLE('=', '=', TOK_EQ, TOK_EQ_EQ);
    DOJI_LEX_CASE_DOUBLE('>', '=', TOK_GT, TOK_GT_EQ);
    DOJI_LEX_CASE_DOUBLE('<', '=', TOK_LT, TOK_LT_EQ);
    DOJI_LEX_CASE_DOUBLE('!', '=', TOK_BANG, TOK_BANG_EQ);
    DOJI_LEX_CASE_DOUBLE('&', '&', TOK_BAND, TOK_AND);
    DOJI_LEX_CASE_DOUBLE('|', '|', TOK_BOR, TOK_OR);
    DOJI_LEX_CASE_SINGLE('~', TOK_BNOT);
  default: {
    if (is_digit(c)) {
      return lex_build_num_tok(lex);
    } else if (is_alpha(c)) {
      return lex_build_ident_tok(lex);
    } else {
      lex_advance(lex);
      lex_init_err(lex, c, tok_type_str(TOK_EOF, lex->alc));
      return (Tok){0};
    }
  }
  }
}

doji_Error const* lex_err(Lexer const* lex) {
  return lex->err;
}