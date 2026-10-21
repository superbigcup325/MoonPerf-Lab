//! gather: the C17 reference implementation.
//!
//! The dataset is a `columnar-gather` stream: `u32 row_count`, then
//! `row_count` × `i64` value, then `row_count` × `u32` index. The kernel
//! gathers the value column through the index vector into an output vector and
//! checksums the result.
//!
//! The generator guarantees every index is in `[0, row_count)`, so the kernel
//! does not run a per-row range check: the question here is the gather loop and
//! its locality, not the cost of an error path.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static uint64_t load_u64_le(const unsigned char* bytes) {
  uint64_t word = 0;
  for (int offset = 0; offset < 8; offset++) {
    word |= (uint64_t)bytes[offset] << (8 * offset);
  }
  return word;
}

static uint32_t load_u32_le(const unsigned char* bytes) {
  uint32_t word = 0;
  for (int offset = 0; offset < 4; offset++) {
    word |= (uint32_t)bytes[offset] << (8 * offset);
  }
  return word;
}

// One gather pass: indirect read into the output vector, then the checksum.
static uint64_t gather(
    const uint64_t* values, const uint32_t* indices, size_t rows) {
  uint64_t* out = malloc(rows * sizeof(uint64_t) + 1);
  if (out == NULL) {
    fail("out of memory");
  }
  for (size_t row = 0; row < rows; row++) {
    // The generator guarantees 0 <= index < rows.
    out[row] = values[indices[row]];
  }
  uint64_t checksum = 0;
  for (size_t row = 0; row < rows; row++) {
    checksum += out[row] * (uint64_t)(row + 1);
  }
  free(out);
  return checksum;
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
  if (length < 4) {
    fail("dataset is shorter than its header");
  }
  const size_t rows = load_u32_le(bytes);
  const size_t expected = 4 + rows * 8 + rows * 4;
  if (length != expected) {
    fprintf(
        stderr,
        "dataset size %zu does not match %zu rows (%zu bytes)\n",
        length,
        rows,
        expected);
    exit(2);
  }

  // Materialize the two columns once, before the timed loop.
  const size_t values_start = 4;
  const size_t indices_start = values_start + rows * 8;
  uint64_t* values = malloc(rows * sizeof(uint64_t) + 1);
  uint32_t* indices = malloc(rows * sizeof(uint32_t) + 1);
  if (values == NULL || indices == NULL) {
    fail("out of memory");
  }
  for (size_t row = 0; row < rows; row++) {
    values[row] = load_u64_le(bytes + values_start + row * 8);
    indices[row] = load_u32_le(bytes + indices_start + row * 4);
  }
  free(bytes);

  uint64_t checksum = 0;
  for (unsigned long long iteration = 0; iteration < repeat; iteration++) {
    barrier();
    checksum = gather(values, indices, rows);
    checksum = keep(checksum);
  }

  FILE* file = fopen(output, "w");
  if (file == NULL) {
    fail_path("cannot write", output);
  }
  fprintf(
      file,
      "{\n  \"rows\": %zu,\n  \"checksum\": \"%016llx\"\n}\n",
      rows,
      (unsigned long long)checksum);
  if (fclose(file) != 0) {
    fail_path("cannot write", output);
  }
  free(values);
  free(indices);
  return 0;
}
