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

void expr_init_lit(Expr* expr, Span span, Lit lit) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIT,
    .data = {.lit = lit},
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

void expr_init_block(Expr* expr, Span span, Stmt const* stmts, size_t len) {
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

void expr_init_call(Expr* expr, Span span, Expr const* fn, Expr const* args, size_t arity) {
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