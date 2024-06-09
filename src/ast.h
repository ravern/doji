#ifndef __doji_ast_h
#define __doji_ast_h

#include "../include/doji.h"
#include "str.h"

/* ---------------- */

typedef struct Span {
  size_t start;
  size_t len;
} Span;

char const* span_str(Span);
void        span_display(Span, StrBuilder*);

/* ---------------- */

typedef enum LitType {
  LIT_NIL,
  LIT_BOOL,
  LIT_INT,
  LIT_FLOAT,
  LIT_STR,
} LitType;

typedef struct Lit {
  Span    span;
  LitType type;
  union {
    bool        b;
    int64_t     i;
    double      f;
    char const* s;
  } data;
} Lit;

void lit_init_nil(Lit*, Span);
void lit_init_bool(Lit*, Span, bool);
void lit_init_int(Lit*, Span, int64_t);
void lit_init_float(Lit*, Span, double);
void lit_init_str(Lit*, Span, char const*);
Span lit_span(Lit const*);

/* ---------------- */

typedef struct Stmt Stmt;

/* ---------------- */

typedef struct Expr Expr;

typedef enum UnaryOp {
  UNARY_OP_NEG,
  UNARY_OP_NOT,
  UNARY_OP_BNOT,
} UnaryOp;

typedef struct UnaryExpr {
  UnaryOp     op;
  Expr const* opr;
} UnaryExpr;

typedef enum BinaryOp {
  BIN_OP_ADD,
  BIN_OP_SUB,
  BIN_OP_MUL,
  BIN_OP_DIV,
  BIN_OP_REM,
  BIN_OP_EQ,
  BIN_OP_NEQ,
  BIN_OP_GT,
  BIN_OP_GTE,
  BIN_OP_LT,
  BIN_OP_LTE,
  BIN_OP_AND,
  BIN_OP_OR,
  BIN_OP_BAND,
  BIN_OP_BOR,
} BinaryOp;

typedef struct BinaryExpr {
  BinaryOp    op;
  Expr const* l_opr;
  Expr const* r_opr;
} BinaryExpr;

typedef struct BlockExpr {
  size_t      len;
  Stmt const* stmts;
} BlockExpr;

typedef struct CallExpr {
  Expr const* fn;
  size_t      arity;
  Expr const* args;
} CallExpr;

typedef enum ExprType {
  EXPR_LIT,
  EXPR_UNARY,
  EXPR_BINARY,
  EXPR_BLOCK,
  EXPR_CALL,
} ExprType;

struct Expr {
  Span     span;
  ExprType type;
  union {
    Lit        lit;
    UnaryExpr  unary;
    BinaryExpr binary;
    BlockExpr  block;
    CallExpr   call;
  } data;
};

void expr_init_lit(Expr*, Span, Lit);
void expr_init_unary(Expr*, Span, UnaryOp, Expr const*);
void expr_init_binary(Expr*, Span, BinaryOp, Expr const*, Expr const*);
void expr_init_block(Expr*, Span, Stmt const*, size_t len);
void expr_init_call(Expr*, Span, Expr const*, Expr const*, size_t arity);
Span expr_span(Expr const*);

/* ---------------- */

typedef enum StmtType {
  STMT_EXPR,
} StmtType;

struct Stmt {
  Span     span;
  StmtType type;
  union {
    Expr expr;
  } data;
};

void stmt_init_expr(Stmt*, Expr);
Span stmt_span(Stmt const*);

/* ---------------- */

typedef struct Ast {
  Stmt const* stmts;
  size_t      len;
} Ast;

void ast_init(Ast*, Stmt const*, size_t len);

/* ---------------- */

#endif