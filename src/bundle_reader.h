#ifndef BUNDLE_READER_H
#define BUNDLE_READER_H 1

#include <stdint.h>
#include <stdio.h>

#include "hash_lookup.h"

typedef enum VermintideGame {
        GAME_VT1 = 1,
        GAME_VT2 = 2,
} VermintideGame;


#define BR_SIGNATURE_V1 (0xF0000004)
#define BR_SIGNATURE_V2 (0xF0000005)

#define BR_HEADER_SIZE (0xC) // 12

typedef struct BundleBlob {
    uint32_t size;
    long position;
    struct BundleBlob* next;
} BundleBlob;

typedef struct BundleItem {
    uint64_t name_hash, type_hash;
    struct BundleItem* next;
} BundleItem;

typedef struct BundleReader {
    char* path;
    FILE* fp;
    HashLookup* lookup;
    int blob_count;
    BundleBlob* blobs;
    int item_count;
    BundleItem* items;
    VermintideGame game;
    uint32_t signature;
    uint32_t file_size;
    uint32_t unzip_size;
    uint32_t padding;
} BundleReader;

int br_open(BundleReader* br, const char* path, VermintideGame game);
void br_close(BundleReader* br);

int br_verify_signature(BundleReader* br);
int br_dump_info(BundleReader* br, FILE* out);
int br_dump_index(BundleReader* br, FILE* out);
int br_read_blobs(BundleReader* br);
void br_destroy_blobs(BundleReader* br);

void br_set_lookup(BundleReader* br, HashLookup* hl);

const char* br_get_path(BundleReader* br);
uint32_t br_get_game(BundleReader* br);

#endif /* BUNDLE_READER_H */
