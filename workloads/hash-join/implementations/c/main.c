//! hash-join: the C17 reference implementation.
//!
//! The dataset is one `structured-records` stream (16-byte records: a `u64` key
//! and a `u64` payload). The first half is the build side, the second half is
//! the probe side. The kernel builds a chained hash table over the build side,
//! probes it with every probe row, and counts the matching (build, probe) pairs
//! plus a wrapping checksum of their payloads.
//!
//! Setup semantics match the Rust and MoonBit implementations: the raw bytes
//! are materialized once into one flat `uint64_t` array before the timed loop,
//! and the table uses 64-bit slot indices with a load factor of at most 0.5.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GAMMA 0x9E3779B97F4A7C15ULL
#define EMPTY UINT64_MAX

// An empty asm with a memory clobber: the optimizer may not hoist the
// invariant kernel out of the repeat loop. Rust uses `black_box` and MoonBit
// `Bench::keep` for the same purpose.
static inline void barrier(void) { __asm__ __volatile__("" ::: "memory"); }

static inline uint64_t keep(uint64_t value) {
  uint64_t spilled = value;
  __asm__ __volatile__("" : "+m"(spilled) : : "memory");
  return spilled;
}

static void fail(const char* message) {
  fprintf(stderr, "%s\n", message);
  exit(2);
}

static void fail_path(const char* message, const char* path) {
  fprintf(stderr, "%s %s\n", message, path);
  exit(2);
}

static const char* option(int argc, char** argv, const char* name) {
  for (int index = 1; index + 1 < argc; index++) {
    if (strcmp(argv[index], name) == 0) {
      return argv[index + 1];
    }
  }
  fail_path("missing option", name);
  return NULL;
}

static inline uint64_t slot_of(uint64_t key, uint64_t mask) {
  return ((key * GAMMA) >> 32) & mask;
}

struct result {
  uint64_t pairs;
  uint64_t checksum;
};

// One join pass: build the table, probe it.
static struct result join(const uint64_t* data, uint64_t rows, uint64_t build_rows) {
  uint64_t table_size = 16;
  while (table_size < build_rows * 2) {
    table_size <<= 1;
  }
  const uint64_t mask = table_size - 1;
  uint64_t* heads = malloc(table_size * sizeof(uint64_t));
  uint64_t* next = malloc(build_rows * sizeof(uint64_t));
  if (heads == NULL || next == NULL) {
    fail("out of memory");
  }
  for (uint64_t index = 0; index < table_size; index++) {
    heads[index] = EMPTY;
  }
  for (uint64_t row = 0; row < build_rows; row++) {
    const uint64_t slot = slot_of(data[row * 2], mask);
    next[row] = heads[slot];
    heads[slot] = row;
  }
  struct result result = {0, 0};
  for (uint64_t row = build_rows; row < rows; row++) {
    const uint64_t key = data[row * 2];
    const uint64_t payload = data[row * 2 + 1];
    uint64_t cursor = heads[slot_of(key, mask)];
    while (cursor != EMPTY) {
      if (data[cursor * 2] == key) {
        result.pairs += 1;
        result.checksum = result.checksum + data[cursor * 2 + 1] + payload;
      }
      cursor = next[cursor];
    }
  }
  free(heads);
  free(next);
  return result;
}

static unsigned char* read_file(const char* path, size_t* length) {
  FILE* file = fopen(path, "rb");
  if (file == NULL) {
    fail_path("cannot read", path);
  }
  if (fseek(file, 0, SEEK_END) != 0) {
    fclose(file);
    fail_path("cannot seek", path);
  }
  long size = ftell(file);
  if (size < 0) {
    fclose(file);
    fail_path("cannot size", path);
  }
  if (fseek(file, 0, SEEK_SET) != 0) {
    fclose(file);
    fail_path("cannot seek", path);
  }
  unsigned char* bytes = malloc((size_t)size + 1);
  if (bytes == NULL) {
    fclose(file);
    fail("out of memory");
  }
  size_t read = fread(bytes, 1, (size_t)size, file);
  fclose(file);
  if (read != (size_t)size) {
    fail_path("cannot read", path);
  }
  *length = (size_t)size;
  return bytes;
}

int main(int argc, char** argv) {
  const char* input = option(argc, argv, "--input");
  const char* output = option(argc, argv, "--output");
  const char* repeat_text = option(argc, argv, "--repeat");
  // The contract passes --params even when the workload declares none.
  (void)option(argc, argv, "--params");

  char* repeat_end = NULL;
  unsigned long long repeat = strtoull(repeat_text, &repeat_end, 10);
  if (repeat_end == repeat_text || *repeat_end != '\0') {
    fail("--repeat must be a non-negative integer");
  }

  size_t length = 0;
  unsigned char* bytes = read_file(input, &length);
  if (length % 16 != 0) {
    fprintf(stderr, "dataset size %zu is not a multiple of 16\n", length);
    exit(2);
  }
  size_t rows = length / 16;
  if (rows == 0 || rows % 2 != 0) {
    fail("the dataset must contain a positive even number of records");
  }
  size_t build_rows = rows / 2;

  // Materialize the records once, before the timed loop.
  uint64_t* data = malloc(rows * 2 * sizeof(uint64_t) + 1);
  if (data == NULL) {
    fail("out of memory");
  }
  for (size_t index = 0; index < rows * 2; index++) {
    uint64_t word = 0;
    for (int offset = 0; offset < 8; offset++) {
      word |= (uint64_t)bytes[index * 8 + offset] << (8 * offset);
    }
    data[index] = word;
  }
  free(bytes);

  struct result result = {0, 0};
  for (unsigned long long iteration = 0; iteration < repeat; iteration++) {
    barrier();
    result = join(data, rows, build_rows);
    result.checksum = keep(result.checksum);
  }

  FILE* file = fopen(output, "w");
  if (file == NULL) {
    fail_path("cannot write", output);
  }
  fprintf(
      file,
      "{\n  \"build_rows\": %zu,\n  \"probe_rows\": %zu,\n  \"pairs\": %llu,\n  \"checksum\": \"%016llx\"\n}\n",
      build_rows,
      rows - build_rows,
      (unsigned long long)result.pairs,
      (unsigned long long)result.checksum);
  if (fclose(file) != 0) {
    fail_path("cannot write", output);
  }
  free(data);
  return 0;
}
