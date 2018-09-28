#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "MurmurHash2.h"

#include "hash_lookup.h"
#include "util.h"


// Create a tuple.
static HashTuple* htuple_new(const char* text)
{
    // Condition already checked elsewhere:
    //     strlen(text) >= sizeof(ht->text)
    HashTuple* ht = malloc(sizeof(*ht));
    if (!ht) return NULL;
    strcpy(ht->text, text);
    ht->hash = MurmurHash64A(text, strlen(text), 0);
    return ht;
}


// Create a tuple and chain it to a list.
static int htuple_prepend(HashTuple** list, const char* text)
{
    HashTuple* tuple = htuple_new(text);
    if (!tuple) return EC_MEMORY_ERROR;
    tuple->next = *list;
    *list = tuple;
    return EC_OK;
}


// Free a list of tuples.
static void htuple_free_list(HashTuple* list)
{
    while (list) {
        HashTuple* next = list->next;
        free(list);
        list = next;
    }
}


// Write a tuple to a file, with a trailing newline.
static void htuple_write(HashTuple* ht, FILE* out)
{
    fprintf(out, "%016"PRIx64" %s\n", ht->hash, ht->text);
}


// Compare two tuples according to hash value.
// Critically fails if a collision is detected.
static int htuple_comp(const void* ht1_ptr, const void* ht2_ptr)
{
    uint64_t hash1 = (*(HashTuple**)ht1_ptr)->hash;
    uint64_t hash2 = (*(HashTuple**)ht2_ptr)->hash;
    return hash1 > hash2 ? 1 : hash1 < hash2 ? -1 : 0;
}


// Initialize a lookup table.
int hl_initialize(HashLookup* hl)
{
    hl->count = 0;
    hl->is_dirty = 0;
    hl->list = NULL;
    hl->array = NULL;
    return 0;
}


// Free the dynamic memory used by a lookup table.
void hl_finalize(HashLookup* hl)
{
    if (!hl) return;
    htuple_free_list(hl->list);
    free(hl->array);
}


// Reads hashes from a file.
int hl_read_from_file(HashLookup* hl, FILE* in)
{
    int count = 0;
    HashTuple* list = NULL;
    HashTuple* first = NULL;
    
    while (1) {
        // Read the next line
        char buffer[256];
        if (!fgets(buffer, sizeof(buffer), in)) {
            if (feof(in)) break;
            count = -1;
            break;
        }

        // Chomp, or fail if we cant
        char* nl = strrchr(buffer, '\n');
        if (!nl) {
            if (!feof(in)) {
                count = -1;
                break;
            }
        }
        else {
            *nl = 0; // Safe to chomp
        }

        if (0 != htuple_prepend(&list, buffer)) {
            count = -1;
            break;
        }

        if (!first) first = list;

        count++;
    }

    // If there was an error, free the new list.
    if (count < 0) htuple_free_list(list);
    else {
        first->next = hl->list;
        hl->list = list;
        hl->is_dirty = 1;
        hl->count += count;
    }
    return count;
}


// Dumps the lookup table to a file.
int hl_write_to_file(HashLookup* hl, FILE* out)
{
    if (hl->is_dirty) {
        int ret = hl_force_rebuild(hl);
        if (EC_OK > ret) return ret;
    }
    for (int i = 0; i < hl->count; ++i) htuple_write(hl->array[i], out);
    return EC_OK;
}


// Create an array from a list. Does not modify the next pointers.
int hl_force_rebuild(HashLookup* hl)
{
    if (!hl->is_dirty) return 0;

    free(hl->array);
    hl->array = malloc(hl->count * sizeof(*hl->array));
    if (!hl->array) return EC_MEMORY_ERROR;

    HashTuple** insert_ptr = hl->array;
    for (HashTuple* tup = hl->list; tup; tup = tup->next) {
        *insert_ptr++ = tup;
    }
    qsort(hl->array, hl->count, sizeof(*hl->array), htuple_comp);

    hl->is_dirty = 0;
    return 1;
}


// Find the inverse of a hash.
int hl_find(HashLookup* hl, uint64_t hash, const char** text)
{
    if (hl->is_dirty) {
        int ret = hl_force_rebuild(hl);
        if (EC_OK > ret) return ret;
    }

    HashTuple tup = { "<needle>", hash, NULL };
    HashTuple* tup_ptr = &tup;

    HashTuple** tup_ptr_ptr = bsearch(
        &tup_ptr, // key
        hl->array, // base
        hl->count, // nel
        sizeof(*hl->array), // width
        htuple_comp // compar
    );

    if (NULL == tup_ptr_ptr) {
        return EC_NOT_FOUND;
    }
    
    *text = (*tup_ptr_ptr)->text;
    return EC_OK;
}
