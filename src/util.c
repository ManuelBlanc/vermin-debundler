#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "util.h"


// Assert that a condition is true. Otherwise, print a message and abort.
void util_assert(
        int condition,
        const char* cond_msg,
        const char* file,
        int line,
        const char* msg_fmt,
        ...
)
{
    if (!condition) {
        fprintf(stderr,
            RED("assertion failed!\n\tCondition : ")
            GREEN("%s")":"YELLOW("%i")": %s\n\t"RED("Message   : "),
            file, line, cond_msg);
        va_list ap;
        va_start(ap, msg_fmt);
        vfprintf(stderr, msg_fmt, ap);
        va_end(ap);
        fputc('\n', stderr);
        exit(EXIT_FAILURE);
    }
}

int util_msb(uint64_t num)
{
    int i = 0;
    while (num >>= 1) i++;
    return i;
}

unsigned char*
util_inflate(unsigned char* in_buffer, size_t in_len, size_t* out_len_ptr)
{
    // Stream initialization
    z_stream strm;
    strm.zalloc   = Z_NULL;
    strm.zfree    = Z_NULL;
    strm.opaque   = Z_NULL;
    strm.avail_in = 0;
    strm.next_in  = Z_NULL;
    strm.avail_out = 0;
    strm.next_out = Z_NULL;
    if (Z_OK != inflateInit(&strm)) return NULL;

    strm.avail_in  = in_len;
    strm.next_in   = in_buffer;

    int ret;
    size_t out_buffer_size = 1 << util_msb(in_len);
    unsigned char* out_buffer = NULL;
    do {
        // If the output buffer is full, we double its size
        if (0 == strm.avail_out) {
            out_buffer_size <<= 1;
            unsigned char* new_out_buffer = realloc(out_buffer, out_buffer_size);
            if (NULL == new_out_buffer) {
                free(out_buffer);
                *out_len_ptr = 0;
                return NULL;
            }
            out_buffer = new_out_buffer;
        }

        // Re-set the input parameters for the new location 
        strm.avail_out = out_buffer_size - strm.total_out;
        strm.next_out  = out_buffer + strm.total_out;

        // Inflate
        // TODO: Maybe handle different errors differently?
        ret = inflate(&strm, Z_NO_FLUSH);
        switch (ret) {
            case Z_STREAM_ERROR: // This is really really bad
            case Z_NEED_DICT:
                ret = Z_DATA_ERROR; // Fall through
            case Z_DATA_ERROR:
            case Z_MEM_ERROR:
                *out_len_ptr = 0;
                free(out_buffer);
                return NULL;
        }

        // Loop if all the available space was consumed
    } while (Z_STREAM_END != ret);

    
    // Resource deallocation (never fails)
    inflateEnd(&strm);

    // Return the results
    *out_len_ptr = strm.total_out;
    return out_buffer;
}


// Print a byte amount in human-readable units.
int util_human_units(char* str, size_t len, uint64_t bytes)
{
    static char *suffix_list[] = { "B", "KiB", "MiB", "GiB", "TiB" };

    int i = 0;
    double dblBytes = (double)bytes;

    if (0 != bytes) {
        while (bytes >>= 10) i++;
        if (i > 4) i = 4;
        dblBytes /= (i * 1024.0);
    }

    return snprintf(str, len, "%.2lf %s", dblBytes, suffix_list[i]);
}


/*
int util_print_human_units(FILE* out,uint64_t bytes)
{
    char buffer[16];
    util_human_units(buffer, sizeof(buffer), bytes);
    return fprintf(out, "%s", buffer);
}
*/


char* util_basename(char* path)
{
    char* base = strrchr(path, '/');
    if (!base || base == path) return path;
    if (0 == base[1]) while (path <= --base && '/' != *base);
    return base + 1;
}


const char* util_code_to_string(ErrorCode code)
{
    switch (code) {
        case EC_MEMORY_ERROR: return "memory error";
        case EC_IO_ERROR: return "io error";
        case EC_BAD_SIGNATURE: return "bad signature";
        case EC_NONZERO_PADDING: return "non-zero padding";
        case EC_SIZE_MISMATCH: return "size mismatch";
        case EC_OK:
        default:
            return NULL;
    }
}


void brP_print_buffer(const void* buffer_raw, size_t len)
{
    const unsigned char* buffer = buffer_raw;
    for (size_t i = 0; i < len; i += 64) {
        for (size_t j = 0; j < 64; ++j) {
            if (i+j < len) {
                printf("%02x", buffer[i+j]);
            }
        }
        printf("\n");
    }
}
