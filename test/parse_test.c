#define __doji_parse_test_c

#include "doji_test.h"

#include "../src/parse.h"

void test_parse(Allocator* alc) {
  Parser prs;
  prs_init(&prs, alc, "<<memory>>", "23 + 32");

  Ast* ast = prs_parse(&prs);
  assert(ast);
  printf("expr->type: %d\n", ast->stmts[0].data.expr.type);
  printf("l expr->type: %lld\n", ast->stmts[0].data.expr.data.binary.l_opr->data.lit.data.i);
  printf("r expr->type: %lld\n", ast->stmts[0].data.expr.data.binary.r_opr->data.lit.data.i);

  prs_destroy(&prs);
}