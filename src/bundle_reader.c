#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

#include "bundle_reader.h"
#include "util.h"


#define to_uint32(ptr) (*(uint32_t*)(ptr))
#define to_uint64(ptr) (*(uint64_t*)(ptr))

// Read a uint32 from a file.
static uint32_t brP_read_uint32(FILE* fp)
{
    unsigned char buffer[4];
    ASSERT(fread(buffer, 4, 1, fp), "Unable to read from file.");
    return to_uint32(buffer);
}


// Open a bundle.
int br_open(BundleReader* br, const char* path, VermintideGame game)
{
    int ret = 0; // Used by ABORT_WITH_CODE (defined in util.h)

    // We do this first to be able to br_close in case of error.
    br->blobs = NULL;

    // Copy the path
    br->fp = fopen(path, "rb");
    br->path = malloc(1 + strlen(path));
    if (NULL == br->fp) ABORT_WITH_CODE(EC_IO_ERROR);
    if (NULL == br->path) ABORT_WITH_CODE(EC_MEMORY_ERROR);

    // Copy misc data
    strcpy(br->path, path);
    br->game = game;
    br->blob_count = 0;
    br->blobs = NULL;
    br->lookup = NULL;

    // Get the file size
    fseek(br->fp, 0L, SEEK_END);
    br->file_size = ftell(br->fp);
    rewind(br->fp);

    // Read header
    br->signature = brP_read_uint32(br->fp);
    br->unzip_size = brP_read_uint32(br->fp);
    br->padding = brP_read_uint32(br->fp);

    // Sanity checks
    if (!br_verify_signature(br)) ABORT_WITH_CODE(EC_BAD_SIGNATURE);
    if (0 != br->padding) ABORT_WITH_CODE(EC_NONZERO_PADDING);

    return EC_OK;

cleanup:
    br_close(br);
    return ret;
}


// Close a bundle.
void br_close(BundleReader* br)
{
    if (NULL == br) return; // Allow calling with NULL ptr.
    free(br->path);
    if (br->fp) fclose(br->fp); // Does not handle NULL
    br_destroy_blobs(br);
}


// Verify the signature of a bundle.
int br_verify_signature(BundleReader* br)
{
    switch (br->game) {
        case GAME_VT1: return (BR_SIGNATURE_V1 == br->signature);
        case GAME_VT2: return (BR_SIGNATURE_V2 == br->signature);
    }
    return 0; // Fail
}


// Read the blob locations.
int br_read_blobs(BundleReader* br)
{
    BundleBlob** prev = &(br->blobs);

    uint32_t size_sum = 0;
    long position = BR_HEADER_SIZE;
    fseek(br->fp, position, SEEK_SET);
    while (position < br->file_size) {
        // Read the size and skip over the blob
        uint32_t size = brP_read_uint32(br->fp);
        position += sizeof(size);
        fseek(br->fp, size, SEEK_CUR);

        // Add it to the list
        BundleBlob* blob = malloc(sizeof(*blob));
        if (NULL == blob) {
            br_destroy_blobs(br);
            return EC_MEMORY_ERROR;
        }
        blob->position = position; // Account for size
        blob->size = size;
        blob->next = NULL;
        *prev = blob;
        prev = &(blob->next);
        br->blob_count++;

        // Update position and total size
        position += size;
        size_sum += size;
    }

    // Sanity check: we have consumed all the file
    if (position != br->file_size) {
        br_destroy_blobs(br);
        return EC_SIZE_MISMATCH;
    }

    return EC_OK;
}


// Utility function to print a hash.
static void print_hash(FILE* out, HashLookup* hl, uint64_t hash)
{
    const char* text;
    if (EC_OK == hl_find(hl, hash, &text)) {
        fprintf(out, "%s", text);
    }
    else {
        fprintf(out, "%"PRIx64, hash);
    }
}


// Write the index of a bundle to a file.
int br_dump_index(BundleReader* br, FILE* out)
{
    if (!br->blobs) {
        int ret = br_read_blobs(br);
        if (EC_OK > ret) return ret;
    }

    BundleBlob* blob1 = br->blobs;
    fseek(br->fp, blob1->position, SEEK_SET);
    unsigned char* buffer = malloc(blob1->size);
    if (NULL == buffer) return EC_MEMORY_ERROR;
    fread(buffer, blob1->size, 1, br->fp);

    size_t out_size;
    unsigned char* out_buffer = util_inflate(buffer, blob1->size, &out_size);

    uint32_t hash_count = to_uint32(out_buffer);
    int hash_block_size = GAME_VT1 == br->game ? 0x10 : 0x14;

    unsigned char* base = out_buffer + 0x104;
    for (uint32_t i = 0; i < hash_count; ++i) {
        int offset = hash_block_size*i;

        // Read the hashes
        uint64_t type_hash = to_uint64(base + offset + 0x0);
        uint64_t name_hash = to_uint64(base + offset + 0x8);
        // In VT2 there is an extra datum at 0x10 that is 4 bytes long.


        fprintf(out, "%i\t", i);
        print_hash(out, br->lookup, name_hash);
        fputc('.', out);
        print_hash(out, br->lookup, type_hash);
        fputc('\n', out);
    }

    free(out_buffer);
    return EC_OK;
}


// Free the memory allocated for the blobs information.
void br_destroy_blobs(BundleReader* br)
{
    BundleBlob* blob = br->blobs;
    while (blob) {
        BundleBlob* next = blob->next;
        free(blob);
        blob = next;
    }
    br->blobs = NULL;
}


// Write some internal information to a file.
int br_dump_info(BundleReader* br, FILE* out)
{
    if (!br->blobs) {
        int ret = br_read_blobs(br);
        if (EC_OK > ret) return ret;
    }

    fprintf(out, "BundleReader(path=\"%s\", game=%i) {\n", br->path, br->game);
    if (br->lookup) {
        const char* basename = util_basename(br->path);
        uint64_t name_hash;
        if (1 == sscanf(basename, "%"SCNx64, &name_hash)) {
            fprintf(out, "\tfilename    = \"");
            print_hash(out, br->lookup, name_hash);
            fprintf(out, "\"\n");
        }
    }
    fprintf(out, "\tsignature   = 0x%x\n", br->signature);
    fprintf(out, "\tunzip_size  = %lu\n", (unsigned long)br->unzip_size);
    fprintf(out, "\tfile_size   = %lu\n", (unsigned long)br->file_size);
    fprintf(out, "\tpadding     = %lu\n", (unsigned long)br->padding);
    fprintf(out, "\tblob_count  = %lu\n", (unsigned long)br->blob_count);
    fprintf(out, "\tblobs       = [\n");
    BundleBlob* item = br->blobs;
    for (; NULL != item; item = item->next) {
        fprintf(out, "\t\tBundleBlob( %7"PRIu32" bytes @ %9ld )\n",
            item->size, item->position);
    }
    fprintf(out, "\t]\n}\n");

    return 0;
}


// Set the hash lookup table.
void br_set_lookup(BundleReader* br, HashLookup* hl)
{
    br->lookup = hl;
}


// Get the path.
const char* br_get_path(BundleReader* br)
{
    return br->path;
}


// Get the game.
uint32_t br_get_game(BundleReader* br)
{
    return br->game;
}
