# Build everything
CC ?= clang
SRC := $(wildcard src/*.c)

.PHONY: all clean
all: build/app

build/app: $(SRC)
	$(CC) -O2 -o $@ $^

clean:
	rm -rf build
