#define __doji_ast_c

#include "ast.h"

/* ---------------- */

Span span_empty() {
  return (Span){
    .start = 0,
    .len = 0,
  };
}

bool span_is_empty(Span span) {
  return span.start == 0 && span.len == 0;
}

char const* span_str(Span span, Allocator* alc) {
  StrBuilder strb;
  strb_init(&strb, alc, 0);
  span_display(span, &strb);
  return strb_build(&strb);
}

void span_display(Span span, StrBuilder* strb) {
  strb_push_size(strb, span.start);
  strb_push_str(strb, "..");
  strb_push_size(strb, span.start + span.len);
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

void cond_init_bool(Cond* cond, Expr* bool_) {
  *cond = (Cond){
    .type = COND_BOOL,
    .data = {.bool_ = bool_},
  };
}

void cond_init_pat(Cond* cond, Pat* pat, Expr* val) {
  *cond = (Cond){
    .type = COND_PAT,
    .data = {.pat = {.pat = pat, .val = val}},
  };
}

/* ---------------- */

void expr_init_nil(Expr* expr, Span span) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIT,
    .data = {.lit = {.type = LIT_NIL, .data = {0}}},
  };
}

void expr_init_bool(Expr* expr, Span span, bool b) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIT,
    .data = {.lit = {.type = LIT_BOOL, .data = {.b = b}}},
  };
}

void expr_init_int(Expr* expr, Span span, int64_t i) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIT,
    .data = {.lit = {.type = LIT_INT, .data = {.i = i}}},
  };
}

void expr_init_float(Expr* expr, Span span, double f) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIT,
    .data = {.lit = {.type = LIT_FLOAT, .data = {.f = f}}},
  };
}

void expr_init_str(Expr* expr, Span span, char const* s) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_LIT,
    .data = {.lit = {.type = LIT_STR, .data = {.s = s}}},
  };
}

void expr_init_ident(Expr* expr, Span span, char const* ident) {
  *expr = (Expr){
    .span = span,
    .type = EXPR_IDENT,
    .data = {.ident = ident},
  };
}

void expr_init_list(Expr* expr, Span span, size_t len, Expr* items) {
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

void expr_init_map(Expr* expr, Span span, size_t len, MapExprEntry* ents) {
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

void expr_init_unary(Expr* expr, Span span, UnaryOp op, Expr* opr) {
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

void expr_init_binary(Expr* expr, Span span, BinaryOp op, Expr* l_opr, Expr* r_opr) {
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

void expr_init_block(Expr* expr, Span span, size_t len, Stmt* stmts) {
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

void expr_init_call(Expr* expr, Span span, Expr* fn, size_t arity, Expr* args) {
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

void ast_init(Ast* ast, Stmt* stmts, size_t len) {
  *ast = (Ast){
    .len = len,
    .stmts = stmts,
  };
}