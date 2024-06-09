#ifndef __doji_h
#define __doji_h

#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------------- */

typedef struct doji_Value doji_Value;

/* ---------------- */

typedef struct doji_Context doji_Context;

typedef struct doji_Error doji_Error;

void        doji_init(doji_Context*);
void        doji_destroy(doji_Context*);
doji_Value  doji_eval(doji_Context*, char const* src);
doji_Error* doji_err(doji_Context*);

/* ---------------- */

typedef enum doji_ValueType {
  DOJI_TYPE_NULL,
  DOJI_TYPE_BOOL,
  DOJI_TYPE_INT,
  DOJI_TYPE_FLOAT,
  DOJI_TYPE_STR,
  DOJI_TYPE_LIST,
  DOJI_TYPE_MAP,
} doji_ValueType;

doji_ValueType doji_get_type(doji_Value);

typedef struct doji_List doji_List;
typedef struct doji_Map  doji_Map;

bool      doji_to_bool(doji_Value);
int64_t   doji_to_int(doji_Value);
double    doji_to_float(doji_Value);
char*     doji_to_str(doji_Value);
doji_List doji_to_list(doji_Value);
doji_Map  doji_to_map(doji_Value);

#endif