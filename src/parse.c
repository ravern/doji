#include "alloc.h"
#include "ast.h"
#include "lex.h"
#define __doji_parse_c

#include "parse.h"

/* ---------------- */

static int64_t parse_int(char const* str) {
  return strtoll(str, NULL, 10);
}

static double parse_float(char const* str) {
  return strtod(str, NULL);
}

/* ---------------- */

static int8_t prefix_bp(TokType op) {
  switch (op) {
  case TOK_HYPHEN:
  case TOK_BANG:
  case TOK_TILDE:  return 19;
  default:         return -1;
  }
}

static int8_t infix_l_bp(TokType op) {
  switch (op) {
  case TOK_BAR_BAR: return 1;
  case TOK_AMP_AMP: return 3;
  case TOK_EQ:
  case TOK_BANG_EQ: return 5;
  case TOK_LT:
  case TOK_LT_EQ:
  case TOK_GT:
  case TOK_GT_EQ:   return 7;
  case TOK_BAR:     return 9;
  case TOK_CARET:   return 11;
  case TOK_AMP:     return 13;
  case TOK_PLUS:
  case TOK_HYPHEN:  return 15;
  case TOK_STAR:
  case TOK_SLASH:
  case TOK_PERCENT: return 17;
  default:          return -1;
  }
}

static int8_t infix_r_bp(TokType op) {
  switch (op) {
  case TOK_BAR_BAR: return 2;
  case TOK_AMP_AMP: return 4;
  case TOK_EQ:
  case TOK_BANG_EQ: return 6;
  case TOK_LT:
  case TOK_LT_EQ:
  case TOK_GT:
  case TOK_GT_EQ:   return 8;
  case TOK_BAR:     return 10;
  case TOK_CARET:   return 12;
  case TOK_AMP:     return 14;
  case TOK_PLUS:
  case TOK_HYPHEN:  return 16;
  case TOK_STAR:
  case TOK_SLASH:
  case TOK_PERCENT: return 18;
  default:          return -1;
  }
}

static uint8_t postfix_bp(TokType op) {
  switch (op) {
  case TOK_PERIOD:    return 20;
  case TOK_L_PAREN:   return 21;
  case TOK_L_BRACKET: return 22;
  default:            return -1;
  }
}

static UnaryOp tok_to_unary_op(TokType op) {
  switch (op) {
  case TOK_HYPHEN: return UNARY_OP_NEG;
  case TOK_BANG:   return UNARY_OP_NOT;
  case TOK_TILDE:  return UNARY_OP_BNOT;
  default:         return -1;
  }
}

static BinaryOp tok_to_binary_op(TokType op) {
  switch (op) {
  case TOK_PLUS:    return BIN_OP_ADD;
  case TOK_HYPHEN:  return BIN_OP_SUB;
  case TOK_STAR:    return BIN_OP_MUL;
  case TOK_SLASH:   return BIN_OP_DIV;
  case TOK_PERCENT: return BIN_OP_REM;
  case TOK_EQ_EQ:   return BIN_OP_EQ;
  case TOK_BANG_EQ: return BIN_OP_NEQ;
  case TOK_GT:      return BIN_OP_GT;
  case TOK_GT_EQ:   return BIN_OP_GTE;
  case TOK_LT:      return BIN_OP_LT;
  case TOK_LT_EQ:   return BIN_OP_LTE;
  case TOK_AMP_AMP: return BIN_OP_AND;
  case TOK_BAR_BAR: return BIN_OP_OR;
  case TOK_AMP:     return BIN_OP_BAND;
  case TOK_BAR:     return BIN_OP_BOR;
  case TOK_CARET:   return BIN_OP_BXOR;
  default:          return -1;
  }
}

/* ---------------- */

void prs_init(Parser* prs, Allocator* alc, char const* path, char const* src) {
  Lexer lex;
  lex_init(&lex, alc, path, src);
  *prs = (Parser){
    .lex = lex,
    .cur_tok = tok_empty(),
    .alc = alc,
    .err = NULL,
  };
}

void prs_destroy(Parser* prs) {
  lex_destroy(&prs->lex);
  if (prs->err) {
    err_destroy(prs->err);
  }
}

doji_Error* prs_err(Parser const* prs) {
  return prs->err;
}

static void prs_init_err(Parser* prs, TokType u, bool has_e, TokType e) {
  StrBuilder strb;
  strb_init(&strb, prs->alc, 0);
  strb_push_str(&strb, "unexpected ");
  tok_type_display(u, &strb);
  if (has_e) {
    strb_push_str(&strb, ", expected ");
    tok_type_display(e, &strb);
  }
  char* msg = strb_build(&strb);
  if (prs->err) {
    err_destroy(prs->err);
  }
  prs->err = alc_alloc(prs->alc, sizeof(doji_Error));
  err_init(prs->err, prs->alc, prs->lex.cur_loc, msg);
}

static doji_Error* prs_forward_lex_err(Parser* prs) {
  if (!prs->lex.err) {
    prs->err = prs->lex.err;
  }
  return prs->err;
}

static Tok prs_peek(Parser* prs) {
  if (tok_is_empty(prs->cur_tok)) {
    prs->cur_tok = lex_next(&prs->lex);
  }
  return prs->cur_tok;
}

static Tok prs_advance(Parser* prs) {
  Tok tok = prs_peek(prs);
  prs->cur_tok = tok_empty();
  return tok;
}

static Tok prs_expect(Parser* prs, TokType e) {
  Tok tok = prs_advance(prs);
  if (tok.type != e) {
    prs_init_err(prs, tok.type, true, e);
  }
  return tok;
}

static void prs_parse_expr(Parser*, Expr*);

static void prs_parse_lit(Parser* prs, Expr* expr) {
  Tok tok = prs_advance(prs);
  switch (tok.type) {
  case TOK_INT: {
    int64_t i = parse_int(&prs->lex.src[tok.span.start]);
    expr_init_int(expr, tok.span, i);
    return;
  }
  case TOK_FLOAT: {
    double f = parse_float(&prs->lex.src[tok.span.start]);
    expr_init_float(expr, tok.span, f);
    return;
  }
  case TOK_TRUE: {
    expr_init_bool(expr, tok.span, true);
    return;
  }
  case TOK_FALSE: {
    expr_init_bool(expr, tok.span, false);
    return;
  }
  case TOK_NIL: {
    expr_init_nil(expr, tok.span);
    return;
  }
  default: {
    prs_init_err(prs, tok.type, false, 0);
    return;
  }
  }
}

static void prs_parse_expr_primary(Parser* prs, Expr* expr) {
  Tok tok = prs_peek(prs);
  if (prs_forward_lex_err(prs) != NULL) {
    return;
  }

  switch (tok.type) {
  case TOK_L_PAREN: {
    prs_advance(prs);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }

    Expr* tmp = alc_alloc(prs->alc, sizeof(Expr));
    prs_parse_expr(prs, tmp);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }

    tok = prs_expect(prs, TOK_R_PAREN);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }

    *expr = *tmp;
    return;
  }
  default: {
    prs_parse_lit(prs, expr);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }
    return;
  }
  }
}

static void prs_parse_expr_postfix(Parser* prs, Expr* expr, Expr* left) {}

static void prs_parse_expr_pratt(Parser* prs, Expr* expr, uint8_t min_bp) {
  Expr* left = alc_alloc(prs->alc, sizeof(Expr));

  Tok tok = prs_peek(prs);
  if (prs_forward_lex_err(prs) != NULL) {
    return;
  }

  int8_t bp = prefix_bp(tok.type);
  if (bp != -1) {
    prs_advance(prs);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }

    Expr* opr = alc_alloc(prs->alc, sizeof(Expr));
    prs_parse_expr_pratt(prs, opr, bp);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }
    UnaryOp op = tok_to_unary_op(tok.type);
    expr_init_unary(left, tok.span, op, opr);
  } else {
    prs_parse_expr_primary(prs, left);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }
  }

  while (true) {
    tok = prs_peek(prs);
    if (prs_forward_lex_err(prs) != NULL) {
      return;
    }

    if (tok.type == TOK_EOF || tok.type == TOK_SEMICOLON || tok.type == TOK_R_BRACE) {
      break;
    }

    int8_t p_bp = postfix_bp(tok.type);
    if (p_bp != -1) {
      if (p_bp < min_bp) {
        break;
      }
      Expr* tmp = alc_alloc(prs->alc, sizeof(Expr));
      prs_parse_expr_postfix(prs, tmp, left);
      if (prs_forward_lex_err(prs) != NULL) {
        return;
      }
      left = tmp;
    }

    int8_t i_l_bp = infix_l_bp(tok.type);
    if (i_l_bp != -1) {
      if (i_l_bp < min_bp) {
        break;
      }

      prs_advance(prs);
      if (prs_forward_lex_err(prs) != NULL) {
        return;
      }

      Expr* right = alc_alloc(prs->alc, sizeof(Expr));
      prs_parse_expr_pratt(prs, right, infix_r_bp(tok.type));
      if (prs_forward_lex_err(prs) != NULL) {
        return;
      }

      BinaryOp op = tok_to_binary_op(tok.type);

      Expr* tmp = alc_alloc(prs->alc, sizeof(Expr));
      expr_init_binary(tmp, tok.span, op, left, right);
      if (prs_forward_lex_err(prs) != NULL) {
        return;
      }
      left = tmp;
    }
  }

  *expr = *left;
}

static void prs_parse_expr(Parser* prs, Expr* expr) {
  return prs_parse_expr_pratt(prs, expr, 0);
}

Ast* prs_parse(Parser* prs) {
  Ast* ast = alc_alloc(prs->alc, sizeof(Ast));

  Expr expr;
  prs_parse_expr(prs, &expr);
  Stmt stmt;
  stmt_init_expr(&stmt, expr);
  Stmt* stmts = alc_alloc(prs->alc, 1 * sizeof(Stmt));
  stmts[0] = stmt;

  ast_init(ast, stmts, 1);
  return ast;
}