#include <errno.h>
#include <getopt.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bundle_reader.h"
#include "hash_lookup.h"
#include "util.h"


// Global configuration
static const char* exe_name = NULL;
static const char* cmd = NULL;
static VermintideGame game = GAME_VT2;
static HashLookup lookup;


// Close the program with an error message.
static void die(const char* fmt, ...)
{
    fprintf(stderr, "%s: ", exe_name);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    hl_finalize(&lookup);
    exit(EXIT_FAILURE);
}

// ACTION: List the loaded hashes in the dictionary.
static int action_dict(int argc, char** argv)
{
    UNUSED(argc);
    UNUSED(argv);
    hl_write_to_file(&lookup, stdout);
    return 0;
}

// ACTION: Dump the structure of a bundle file.
static int action_dump(int argc, char** argv)
{
    if (1 == argc ) die("no bundle files provided");
    for (int i = 1; i < argc; ++i) {
        BundleReader br;
        int ret = br_open(&br, argv[i], game);
        if (EC_OK == ret) {
            br_set_lookup(&br, &lookup);
            br_dump_info(&br, stdout);
            br_close(&br);
        }
        else {
            die("BundleReader(\"%s\"): %s", argv[i], util_code_to_string(ret));
        }
    }
    return 0;
}


// ACTION: Print the program usage in stderr.
static void usage(void); // Need to forward declare this.
static int action_help(int argc, char** argv)
{
    UNUSED(argc); UNUSED(argv);
    usage();
    return 0;
}


// List the contents of the bundles.
static int action_list(int argc, char** argv)
{
    if (1 == argc) die("no bundle files provided");
    for (int i = 1; i < argc; ++i) {
        BundleReader br;
        int ret = br_open(&br, argv[i], game);
        if (EC_OK == ret) {
            br_set_lookup(&br, &lookup);
            fprintf(stdout, "BundleReader(%s) [\n", argv[i]);
            br_dump_index(&br, stdout);
            br_close(&br);
            fprintf(stdout, "]\n");
        }
        else {
            die("BundleReader(\"%s\"): %s", argv[i], util_code_to_string(ret));
            return 1;
        }
    }
    return 0;
}

// Structure to hold subcommand information.
static struct Action {
    const char* cmd;
    int (*thunk)(int argc, char** argv);
    const char* help;
} SUB_CMDS[] = {
    { "dict", action_dict, "Print the generated hash lookup dictionary." },
    { "dump", action_dump, "Dump some internal bundle information." },
    { "help", action_help, "Print this help." },
    { "list", action_list, "List the assets inside the bundle." },
    {NULL,NULL,NULL},
};


// OPTION: Read hashes from a file
static void option_read_hashes(const char* path)
{
    FILE* in = fopen(path, "r");
    if (!in) die("%s: %s", path, strerror(errno));
    hl_read_from_file(&lookup, in);
    fclose(in);
}

// OPTION: Select the bundle type.
static void option_read_game(const char* num_str)
{
    switch (atoi(num_str)) {
        case 1: game = GAME_VT1; return;
        case 2: game = GAME_VT2; return;
        default: die("invalid (game=%s). must be 1 or 2\n", optarg);
    }
}

#define usage_block(name) fprintf(stderr, "\n%s:\n", name);   
#define usage_line(key, help) fprintf(stderr, "  %-20s %s\n", key, help);
static void usage(void)
{
    fprintf(stderr, "Usage: %s [options..] command [args..]\n", exe_name);

    /**/usage_block("Options");
    usage_line("-g, --game=1|2", "Select the game bundle version.");
    usage_line("-l, --lookup=PATH", "Load a hash lookup file. Can be repeated.");
    /**/usage_block("Commands");
    for (int i = 0; SUB_CMDS[i].cmd; ++i) {
        usage_line(SUB_CMDS[i].cmd, SUB_CMDS[i].help);
    }
}

int main(int argc, char** argv)
{
    // Command line long options
    static struct option longopts[] = {
        { "help", no_argument, NULL, 'h' },
        { "lookup", required_argument, NULL, 'l' },
        { "game", required_argument, NULL, 'g' },
        { NULL,0,NULL,0 },
    };

    exe_name = util_basename(argv[0]); // Store the exe in file global
    hl_initialize(&lookup);

    while (1) {
        int opt = getopt_long(argc, argv, "hl:g:", longopts, NULL);
        if (-1 == opt) break;
        switch (opt) {
            case ':': die("missing argument");
            case '?': die("unknown or ambiguous option");
            case 'h': usage(); return 0;
            case 'l': option_read_hashes(optarg); break;
            case 'g': option_read_game(optarg); break;
        }
    }
    argc -= optind;
    argv += optind;

    cmd = argv[0]; // Store the command in file global

    // No arguments
    if (0 == argc) cmd = "help";

    // Find and execute the action verb.
    for (int i = 0; SUB_CMDS[i].cmd; ++i) {
        if (0 == strcmp(SUB_CMDS[i].cmd, cmd)) {
            int ret = SUB_CMDS[i].thunk(argc, argv);
            hl_finalize(&lookup);
            return ret;
        }
    }

    // If we reached this point,
    die("'%s' is not a valid command. See '%s help'.", cmd, exe_name);
}
