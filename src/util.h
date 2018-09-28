#ifndef UTIL_H
#define UTIL_H

#include <stdint.h>

#define UNUSED(arg) ((void)(arg))
#define MACRO_BODY(BLOCK) do { BLOCK } while (0)
#define ABORT_WITH_CODE(code) MACRO_BODY( ret = (code); goto cleanup; )


#define ASSERT(condition, ...) \
    util_assert(condition, (#condition), __FILE__, __LINE__, __VA_ARGS__)
void util_assert(
    int condition,
    const char* cond_msg,
    const char* file,
    int line,
    const char* msg_fmt,
    ...
);

int util_msb(uint64_t num);

unsigned char*
util_inflate(unsigned char* in_buffer, size_t in_len, size_t* out_len_ptr);

int util_human_units(char* str, size_t len, uint64_t bytes);

char* util_basename(char* path);


#define RED(str) "\033[31m" str "\033[0m"
#define GREEN(str) "\033[32m" str "\033[0m"
#define YELLOW(str) "\033[33m" str "\033[0m"

#define UNUSED(arg) ((void)(arg))

typedef enum ErrorCode {
    EC_OK               = 0,
    EC_MEMORY_ERROR     = -1,
    EC_IO_ERROR         = -2,
    EC_BAD_SIGNATURE    = -3,
    EC_NONZERO_PADDING  = -4,
    EC_SIZE_MISMATCH    = -5,
    EC_NOT_FOUND        = -6,
} ErrorCode;

#define EC_IS_OK(code)   (EC_OK <= (code))

const char* util_code_to_string(ErrorCode code);

#endif /* UTIL_H */
