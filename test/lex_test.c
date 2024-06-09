#define __doji_lex_test_c

#include "doji_test.h"

#include "../src/lex.h"

void test_lex(Allocator* alc) {
  Lexer lex;
  lex_init(&lex, alc, "<<memory>>", "1 + 2 * 3.2 / nil - false");

  Tok one = lex_next(&lex);
  assert(!lex.err);
  assert(one.type == TOK_INT);
  assert(one.span.start == 0);
  assert(one.span.len == 1);

  Tok plus = lex_next(&lex);
  assert(!lex.err);
  assert(plus.type == TOK_PLUS);
  assert(plus.span.start == 2);
  assert(plus.span.len == 1);

  Tok two = lex_next(&lex);
  assert(!lex.err);
  assert(two.type == TOK_INT);
  assert(two.span.start == 4);
  assert(two.span.len == 1);

  Tok mul = lex_next(&lex);
  assert(!lex.err);
  assert(mul.type == TOK_STAR);
  assert(mul.span.start == 6);
  assert(mul.span.len == 1);

  Tok three = lex_next(&lex);
  assert(!lex.err);
  assert(three.type == TOK_FLOAT);
  assert(three.span.start == 8);
  assert(three.span.len == 3);

  Tok div = lex_next(&lex);
  assert(!lex.err);
  assert(div.type == TOK_SLASH);
  assert(div.span.start == 12);
  assert(div.span.len == 1);

  Tok nil = lex_next(&lex);
  assert(!lex.err);
  assert(nil.type == TOK_NIL);
  assert(nil.span.start == 14);
  assert(nil.span.len == 3);

  Tok sub = lex_next(&lex);
  assert(!lex.err);
  assert(sub.type == TOK_HYPHEN);
  assert(sub.span.start == 18);
  assert(sub.span.len == 1);

  Tok fals = lex_next(&lex);
  assert(!lex.err);
  assert(fals.type == TOK_FALSE);
  assert(fals.span.start == 20);
  assert(fals.span.len == 5);

  lex_destroy(&lex);
}