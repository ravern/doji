#ifndef __doji_test_h
#define __doji_test_h

#include <assert.h>
#include <stdio.h>

#include "../include/doji.h"

#include "../src/alloc.h"

void test_vector(Allocator*);
void test_lex(Allocator*);
void test_parse(Allocator*);

#endif