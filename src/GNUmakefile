# Definitions
EXE := main
SRC := $(wildcard *.c)
OBJ := $(SRC:.c=.o)
DEP := $(SRC:.c=.d)


# Configuration
CFLAGS := -g -std=c99 -pedantic -Wall -Werror -Wextra
CFLAGS += -Wno-unused-function
LDLIBS := -lz


# Phony
.PHONY: all clean
all: $(EXE)
clean:
	$(RM) $(OBJ) $(DEP) $(EXES)


# Linker dependencies
$(EXE): $(OBJ)


# Compiler dependencies
CFLAGS += -MMD
-include $(DEP)
