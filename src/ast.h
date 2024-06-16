#ifndef __doji_ast_h
#define __doji_ast_h

#include "../include/doji.h"

#include "str.h"

/* ---------------- */

typedef struct Span {
  size_t start;
  size_t len;
} Span;

Span        span_empty();
bool        span_is_empty(Span);
char const* span_str(Span, Allocator*);
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
  LitType type;
  union {
    bool        b;
    int64_t     i;
    double      f;
    char const* s;
  } data;
} Lit;

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
  size_t len;
  Expr*  items;
} ListExpr;

typedef struct MapExprEntry {
  Expr* key;
  Expr* val;
} MapExprEntry;

typedef struct MapExpr {
  size_t        len;
  MapExprEntry* ents;
} MapExpr;

typedef enum UnaryOp {
  UNARY_OP_NEG,
  UNARY_OP_NOT,
  UNARY_OP_BNOT,
} UnaryOp;

typedef struct UnaryExpr {
  UnaryOp op;
  Expr*   opr;
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
  BIN_OP_BXOR,
} BinaryOp;

typedef struct BinaryExpr {
  BinaryOp op;
  Expr*    l_opr;
  Expr*    r_opr;
} BinaryExpr;

typedef struct BlockExpr {
  size_t len;
  Stmt*  stmts;
  bool   has_ret;
} BlockExpr;

typedef struct CallExpr {
  Expr*  fn;
  size_t arity;
  Expr*  args;
} CallExpr;

typedef enum CondType {
  COND_BOOL,
  COND_PAT,
} CondType;

typedef struct PatCond {
  Pat*  pat;
  Expr* val;
} PatCond;

typedef struct Cond {
  CondType type;
  union {
    Expr*   bool_;
    PatCond pat;
  } data;
} Cond;

void cond_init_bool(Cond*, Expr*);
void cond_init_pat(Cond*, Pat*, Expr*);

typedef struct IfExpr {
  Cond  cond;
  Expr* then;
  Expr* else_;
} IfExpr;

typedef struct WhileExpr {
  Cond  cond;
  Expr* body;
} WhileExpr;

typedef struct ForExpr {
  char const* ident;
  Expr*       body;
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

void expr_init_nil(Expr*, Span);
void expr_init_bool(Expr*, Span, bool);
void expr_init_int(Expr*, Span, int64_t);
void expr_init_float(Expr*, Span, double);
void expr_init_str(Expr*, Span, char const*);
void expr_init_ident(Expr*, Span, char const*);
void expr_init_list(Expr*, Span, size_t len, Expr*);
void expr_init_map(Expr*, Span, size_t len, MapExprEntry*);
void expr_init_unary(Expr*, Span, UnaryOp, Expr*);
void expr_init_binary(Expr*, Span, BinaryOp, Expr*, Expr*);
void expr_init_block(Expr*, Span, size_t len, Stmt*);
void expr_init_call(Expr*, Span, Expr*, size_t arity, Expr*);
void expr_init_if(Expr*, Span, Cond, Expr*, Expr*);
void expr_init_while(Expr*, Span, Cond, Expr*);
void expr_init_for(Expr*, Span, char const*, Expr*);
Span expr_span(Expr const*);
void expr_display(Expr const*, StrBuilder*);
void expr_str(Expr const*, Allocator*);

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
void stmt_display(Stmt const*, StrBuilder*);
void stmt_str(Stmt const*, Allocator*);

/* ---------------- */

typedef struct Ast {
  Stmt*  stmts;
  size_t len;
} Ast;

void ast_init(Ast*, Stmt*, size_t len);
void ast_display(Ast const*, StrBuilder*);
void ast_str(Ast const*, Allocator*);

/* ---------------- */

#endif