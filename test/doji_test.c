#define __doji_test_c

#include "doji_test.h"

static Allocator make_std_alc(jmp_buf* err_buf) {
  return (Allocator){
    .err_buf = err_buf,
    .alloc = malloc,
    .realloc = realloc,
    .free = free,
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

  return 0;
}