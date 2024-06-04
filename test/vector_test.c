
#include <stdint.h>
#define __doji_vector_test_c

#include "doji_test.h"

#include "../src/vector.h"

void test_vector(Allocator* alc) {
  Vector vec;
  vec_init(&vec, alc, 4, sizeof(int64_t));

  vec_push(&vec, &(int64_t){1});
  vec_push(&vec, &(int64_t){2});
  vec_push(&vec, &(int64_t){3});
  vec_push(&vec, &(int64_t){4});

  assert(vec_len(&vec) == 4);

  assert(*(int64_t*)vec_get(&vec, 0) == 1);
  assert(*(int64_t*)vec_get(&vec, 1) == 2);
  assert(*(int64_t*)vec_get(&vec, 2) == 3);
  assert(*(int64_t*)vec_get(&vec, 3) == 4);

  vec_set(&vec, 2, &(int64_t){5});

  assert(*(int64_t*)vec_get(&vec, 2) == 5);

  vec_destroy(&vec);
}