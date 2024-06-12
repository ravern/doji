#define __doji_ast_c

#include "ast.h"

/* ---------------- */

void lit_init_nil(Lit* lit, Span span) {
  *lit = (Lit){
    .span = span,
    .type = LIT_NIL,
    .data = {0},
  };
}

void lit_init_bool(Lit* lit, Span span, bool b) {
  *lit = (Lit){
    .span = span,
    .type = LIT_BOOL,
    .data = {.b = b},
  };
}

void lit_init_int(Lit* lit, Span span, int64_t i) {
  *lit = (Lit){
    .span = span,
    .type = LIT_INT,
    .data = {.i = i},
  };
}

void lit_init_float(Lit* lit, Span span, double f) {
  *lit = (Lit){
    .span = span,
    .type = LIT_FLOAT,
    .data = {.f = f},
  };
}

void lit_init_str(Lit* lit, Span span, char const* s) {
  *lit = (Lit){
    .span = span,
    .type = LIT_STR,
    .data = {.s = s},
  };
}

Span lit_span(Lit const* lit) {
  return lit->span;
}

/* ---------------- */

void pat_init_ident(Pat* pat, Span span, char const* ident) {
  *pat = (Pat){
    .span = span,
    .type = PAT_IDENT,
    .data = {.ident = ident},
  };
}

Span pat_span(Pat const* pat) {
  return pat->span;
}

/* ---------------- */

void cond_init_bool(Cond* cond, Expr const* bool_) {
  *cond = (Cond){
    .type = COND_BOOL,
    .data = {.bool_ = bool_},
  };
}

void cond_init_pat(Cond* cond, Pat const* pat, Expr const* val) {
  *cond = (Cond){
    .type = COND_PAT,
    .data = {.pat = {.pat = pat, .val = val}},
  };
}

/* ---------------- */

void expr_init_lit(Expr* expr, Span span, Lit lit) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIT,
    .data = {.lit = lit},
  };
}

void expr_init_ident(Expr* expr, Span span, char const* ident) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_IDENT,
    .data = {.ident = ident},
  };
}

void expr_init_list(Expr* expr, Span span, size_t len, Expr const* items) {
  ListExpr list = {
    .len = len,
    .items = items,
  };
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIST,
    .data = {.list = list},
  };
}

void expr_init_map(Expr* expr, Span span, size_t len, MapExprEntry const* ents) {
  MapExpr map = {
    .len = len,
    .ents = ents,
  };
  *expr = (Expr){
    .span = span,
    .type = EXPR_MAP,
    .data = {.map = map},
  };
}

void expr_init_unary(Expr* expr, Span span, UnaryOp op, Expr const* opr) {
  UnaryExpr unary = {
    .op = op,
    .opr = opr,
  };
  *expr = (Expr){
    .span = span,
    .type = EXPR_UNARY,
    .data = {.unary = unary},
  };
}

void expr_init_binary(Expr* expr, Span span, BinaryOp op, Expr const* l_opr, Expr const* r_opr) {
  BinaryExpr binary = {
    .op = op,
    .l_opr = l_opr,
    .r_opr = r_opr,
  };
  *expr = (Expr){
    .span = span,
    .type = EXPR_BINARY,
    .data = {.binary = binary},
  };
}

void expr_init_block(Expr* expr, Span span, size_t len, Stmt const* stmts) {
  BlockExpr block = {
    .len = len,
    .stmts = stmts,
  };
  *expr = (Expr){
    .span = span,
    .type = EXPR_BLOCK,
    .data = {.block = block},
  };
}

void expr_init_call(Expr* expr, Span span, Expr const* fn, size_t arity, Expr const* args) {
  CallExpr call = {
    .fn = fn,
    .arity = arity,
    .args = args,
  };
  *expr = (Expr){
    .span = span,
    .type = EXPR_CALL,
    .data = {.call = call},
  };
}

Span expr_span(Expr const* expr) {
  return expr->span;
}

/* ---------------- */

void stmt_init_expr(Stmt* stmt, Expr expr) {
  *stmt = (Stmt){
    .type = STMT_EXPR,
    .data = {.expr = expr},
  };
}

Span stmt_span(Stmt const* stmt) {
  return stmt->span;
}

/* ---------------- */

void ast_init(Ast* ast, Stmt const* stmts, size_t len) {
  *ast = (Ast){
    .len = len,
    .stmts = stmts,
  };
}