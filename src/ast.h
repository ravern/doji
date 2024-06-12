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

typedef struct Pat Pat;

typedef enum PatType {
  PAT_IDENT,
} PatType;

struct Pat {
  Span    span;
  PatType type;
  union {
    char const* ident;
  } data;
};

void pat_init_ident(Pat*, Span, char const*);
Span pat_span(Pat const*);

/* ---------------- */

typedef struct Stmt Stmt;

/* ---------------- */

typedef struct Expr Expr;

typedef struct ListExpr {
  size_t      len;
  Expr const* items;
} ListExpr;

typedef struct MapExprEntry {
  Expr const* key;
  Expr const* val;
} MapExprEntry;

typedef struct MapExpr {
  size_t              len;
  MapExprEntry const* ents;
} MapExpr;

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
  bool        has_ret;
} BlockExpr;

typedef struct CallExpr {
  Expr const* fn;
  size_t      arity;
  Expr const* args;
} CallExpr;

typedef enum CondType {
  COND_BOOL,
  COND_PAT,
} CondType;

typedef struct PatCond {
  Pat const*  pat;
  Expr const* val;
} PatCond;

typedef struct Cond {
  CondType type;
  union {
    Expr const* bool_;
    PatCond     pat;
  } data;
} Cond;

void cond_init_bool(Cond*, Expr const*);
void cond_init_pat(Cond*, Pat const*, Expr const*);
void cond_destroy(Cond*);

typedef struct IfExpr {
  Cond        cond;
  Expr const* then;
  Expr const* else_;
} IfExpr;

typedef struct WhileExpr {
  Cond        cond;
  Expr const* body;
} WhileExpr;

typedef struct ForExpr {
  char const* ident;
  Expr const* body;
} ForExpr;

typedef enum ExprType {
  EXPR_LIT,
  EXPR_IDENT,
  EXPR_LIST,
  EXPR_MAP,
  EXPR_UNARY,
  EXPR_BINARY,
  EXPR_BLOCK,
  EXPR_CALL,
  EXPR_IF,
  EXPR_WHILE,
  EXPR_FOR,
} ExprType;

struct Expr {
  Span     span;
  ExprType type;
  union {
    Lit         lit;
    char const* ident;
    ListExpr    list;
    MapExpr     map;
    UnaryExpr   unary;
    BinaryExpr  binary;
    BlockExpr   block;
    CallExpr    call;
    IfExpr      if_;
    WhileExpr   while_;
    ForExpr     for_;
  } data;
};

void expr_init_lit(Expr*, Span, Lit);
void expr_init_ident(Expr*, Span, char const*);
void expr_init_list(Expr*, Span, size_t len, Expr const*);
void expr_init_map(Expr*, Span, size_t len, MapExprEntry const*);
void expr_init_unary(Expr*, Span, UnaryOp, Expr const*);
void expr_init_binary(Expr*, Span, BinaryOp, Expr const*, Expr const*);
void expr_init_block(Expr*, Span, size_t len, Stmt const*);
void expr_init_call(Expr*, Span, Expr const*, size_t arity, Expr const*);
void expr_init_if(Expr*, Span, Cond, Expr const*, Expr const*);
void expr_init_while(Expr*, Span, Cond, Expr const*);
void expr_init_for(Expr*, Span, char const*, Expr const*);
void expr_destroy(Expr*);
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