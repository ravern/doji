#define __doji_lex_test_c

#include "doji_test.h"

#include "../src/lex.h"

void test_lex(Allocator* alc) {
  Lexer lex;
  lex_init(
      &lex, alc, "<<memory>>",
      "1 + 2 * 3.2 / nil - false\n"
      "true () [1] {foo}\n");

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

  Tok tru = lex_next(&lex);
  assert(!lex.err);
  assert(tru.type == TOK_TRUE);
  assert(tru.span.start == 26);
  assert(tru.span.len == 4);

  Tok l_paren = lex_next(&lex);
  assert(!lex.err);
  assert(l_paren.type == TOK_L_PAREN);
  assert(l_paren.span.start == 31);
  assert(l_paren.span.len == 1);

  Tok r_paren = lex_next(&lex);
  assert(!lex.err);
  assert(r_paren.type == TOK_R_PAREN);
  assert(r_paren.span.start == 32);
  assert(r_paren.span.len == 1);

  Tok l_bracket = lex_next(&lex);
  assert(!lex.err);
  assert(l_bracket.type == TOK_L_BRACKET);
  assert(l_bracket.span.start == 34);
  assert(l_bracket.span.len == 1);

  Tok another_one = lex_next(&lex);
  assert(!lex.err);
  assert(another_one.type == TOK_INT);
  assert(another_one.span.start == 35);
  assert(another_one.span.len == 1);

  Tok r_bracket = lex_next(&lex);
  assert(!lex.err);
  assert(r_bracket.type == TOK_R_BRACKET);
  assert(r_bracket.span.start == 36);
  assert(r_bracket.span.len == 1);

  Tok l_brace = lex_next(&lex);
  assert(!lex.err);
  assert(l_brace.type == TOK_L_BRACE);
  assert(l_brace.span.start == 38);
  assert(l_brace.span.len == 1);

  Tok foo = lex_next(&lex);
  assert(!lex.err);
  assert(foo.type == TOK_IDENT);
  assert(foo.span.start == 39);
  assert(foo.span.len == 3);

  Tok r_brace = lex_next(&lex);
  assert(!lex.err);
  assert(r_brace.type == TOK_R_BRACE);
  assert(r_brace.span.start == 42);
  assert(r_brace.span.len == 1);

  Tok eof = lex_next(&lex);
  assert(!lex.err);
  assert(eof.type == TOK_EOF);
  assert(eof.span.start == 44);
  assert(eof.span.len == 0);

  Tok another_eof = lex_next(&lex);
  assert(!lex.err);
  assert(eof.type == TOK_EOF);
  assert(eof.span.start == 44);
  assert(eof.span.len == 0);

  lex_destroy(&lex);
}