#define __doji_test_c

#include "doji_test.h"

#include "../src/lex.h"

void* std_alloc(void* state, size_t size) {
  return malloc(size);
}

void* std_realloc(void* state, void* data, size_t size) {
  return realloc(data, size);
}

void std_free(void* state, void* data) {
  free(data);
}

static Allocator make_std_alc(jmp_buf* err_buf) {
  return (Allocator){
    .state = NULL,
    .err_buf = err_buf,
    .alloc = std_alloc,
    .realloc = std_realloc,
    .free = std_free,
  };
}

int main() {
  jmp_buf err_buf;

  Allocator alc = make_std_alc(&err_buf);

  int code = setjmp(err_buf);
  if (code != 0) {
    fprintf(stderr, "doji_test: error: out of memory\n");
    return 1;
  }

  test_vector(&alc);
  test_lex(&alc);

  return 0;
}