#ifndef HASH_LOOKUP_H
#define HASH_LOOKUP_H

#include <stdint.h>


typedef struct HashTuple {
    // Biggest to smallest
    char text[256];
    uint64_t hash;
    struct HashTuple* next;
} HashTuple;


typedef struct HashLookup {
    int count;
    int is_dirty;
    HashTuple* list;
    HashTuple** array;
} HashLookup;


int hl_initialize(HashLookup* hl);
void hl_finalize(HashLookup* hl);

int hl_append(HashLookup* hl, const char* text);

int hl_read_from_file(HashLookup* hl, FILE* in);
int hl_write_to_file(HashLookup* hl, FILE* out);

int hl_force_rebuild(HashLookup* hl);

int hl_find(HashLookup* lookup, uint64_t hash, const char** text);

#endif /* HASH_LOOKUP_H */
