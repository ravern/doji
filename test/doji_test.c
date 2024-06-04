#define __doji_test_c

#include "doji_test.h"

static Allocator make_test_alc(jmp_buf* err_buf) {
  Allocator alc;
  alc.err_buf = err_buf;
  alc.alloc = malloc;
  alc.realloc = realloc;
  alc.free = free;
  return alc;
}

int main() {
  jmp_buf err_buf;

  Allocator alc = make_test_alc(&err_buf);

  int code = setjmp(err_buf);
  if (code != 0) {
    fprintf(stderr, "doji_test: error: out of memory\n");
    return 1;
  }

  test_vector(&alc);

  return 0;
}