#define __doji_str_c

#include "str.h"

/* ---------------- */

#define DOJI_STRB_DEFAULT_INIT_CAP 64
#define DOJI_STRB_SIZE_BUF_LEN     24

/* ---------------- */

void strb_init(StrBuilder* strb, Allocator const* alc, size_t init_cap) {
  size_t actual_init_cap = init_cap != 0 ? init_cap : DOJI_STRB_DEFAULT_INIT_CAP;

  Vector str;
  vec_init(&str, alc, actual_init_cap, sizeof(char));

  *strb = (StrBuilder){.str = &str};
}

void strb_destroy(StrBuilder* strb) {
  vec_destroy(strb->str);
}

void strb_push(StrBuilder* strb, char c) {
  vec_push(strb->str, &c);
}

void strb_push_str(StrBuilder* strb, char const* str) {
  for (size_t i = 0; str[i] != '\0'; ++i) {
    strb_push(strb, str[i]);
  }
}

void strb_push_size(StrBuilder* strb, size_t n) {
  char   buf[DOJI_STRB_SIZE_BUF_LEN];
  size_t len = snprintf(buf, sizeof(buf) / sizeof(char), "%zu", n);
  for (size_t i = 0; i < len; i++) {
    strb_push(strb, buf[i]);
  }
}

void strb_push_int64(StrBuilder* strb, int64_t i) {
  char   buf[DOJI_STRB_SIZE_BUF_LEN];
  size_t len = snprintf(buf, sizeof(buf) / sizeof(char), "%lld", i);
  for (size_t i = 0; i < len; i++) {
    strb_push(strb, buf[i]);
  }
}

char const* strb_build(StrBuilder* strb) {
  strb_push(strb, '\0');
  return (char const*)vec_get(strb->str, 0);
}