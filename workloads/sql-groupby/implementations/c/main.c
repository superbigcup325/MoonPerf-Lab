//! sql-groupby: the C17 reference implementation.
//!
//! The dataset is a `csv-records` file: `id,category,amount` and one row per
//! record. The kernel parses the CSV and answers one fixed query:
//!
//!   SELECT category, count(*) AS n, sum(amount) AS total
//!   FROM t GROUP BY category ORDER BY category
//!
//! and folds the result into a checksum: for output row `i`, add
//! `n * (i + 1) + total` to a wrapping 64-bit accumulator.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CATEGORIES 4096

// An empty asm with a memory clobber: the optimizer may not hoist the
// invariant kernel out of the repeat loop.
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

struct result {
  uint64_t groups;
  uint64_t rows;
  uint64_t checksum;
};

// Parse one decimal integer, stopping at a delimiter.
static uint64_t parse_number(const unsigned char* bytes, size_t length, size_t* cursor) {
  uint64_t value = 0;
  int digits = 0;
  while (*cursor < length) {
    unsigned char byte = bytes[*cursor];
    if (byte < '0' || byte > '9') {
      break;
    }
    value = value * 10 + (uint64_t)(byte - '0');
    digits += 1;
    *cursor += 1;
  }
  if (digits == 0) {
    fail("csv: expected a decimal integer");
  }
  return value;
}

static struct result query(const unsigned char* bytes, size_t length) {
  static uint64_t counts[CATEGORIES];
  static uint64_t totals[CATEGORIES];
  memset(counts, 0, sizeof counts);
  memset(totals, 0, sizeof totals);
  struct result result = {0, 0, 0};
  size_t cursor = 0;

  // Header: skip to the first newline.
  while (cursor < length && bytes[cursor] != '\n') {
    cursor += 1;
  }
  if (cursor < length) {
    cursor += 1;
  }

  while (cursor < length) {
    (void)parse_number(bytes, length, &cursor);
    if (cursor >= length || bytes[cursor] != ',') {
      fail("csv: expected ',' after id");
    }
    cursor += 1;
    uint64_t category = parse_number(bytes, length, &cursor);
    if (cursor >= length || bytes[cursor] != ',') {
      fail("csv: expected ',' after category");
    }
    cursor += 1;
    uint64_t amount = parse_number(bytes, length, &cursor);
    if (cursor < length && bytes[cursor] == '\r') {
      cursor += 1;
    }
    if (cursor < length && bytes[cursor] == '\n') {
      cursor += 1;
    }
    if (category >= CATEGORIES) {
      fail("csv: category out of the declared range");
    }
    counts[category] += 1;
    totals[category] += amount;
    result.rows += 1;
  }

  for (size_t slot = 0; slot < CATEGORIES; slot++) {
    if (counts[slot] == 0) {
      continue;
    }
    result.groups += 1;
    result.checksum += counts[slot] * result.groups;
    result.checksum += totals[slot];
  }
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
  struct result result = {0, 0, 0};
  for (unsigned long long iteration = 0; iteration < repeat; iteration++) {
    barrier();
    result = query(bytes, length);
    result.checksum = keep(result.checksum);
  }

  FILE* file = fopen(output, "w");
  if (file == NULL) {
    fail_path("cannot write", output);
  }
  fprintf(
      file,
      "{\n  \"groups\": %llu,\n  \"rows\": %llu,\n  \"checksum\": \"%016llx\"\n}\n",
      (unsigned long long)result.groups,
      (unsigned long long)result.rows,
      (unsigned long long)result.checksum);
  if (fclose(file) != 0) {
    fail_path("cannot write", output);
  }
  free(bytes);
  return 0;
}
