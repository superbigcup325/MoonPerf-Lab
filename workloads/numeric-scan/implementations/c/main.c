//! numeric-scan: the C17 reference implementation.
//!
//! One sequential pass over an `f64` array, accumulating sum, sum of squares,
//! min, max and the number of values above a threshold. The adapter contract
//! (protocol section 5) passes the dataset, the params file, the output path
//! and the inner repeat count on the command line.
//!
//! Setup semantics match the Rust reference and the MoonBit implementation:
//! the raw little-endian bytes are materialized into one `double` per input
//! before the kernel runs, and the input length must be a multiple of 8.

#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// A compiler barrier across the repeat loop: an empty asm with a memory
// clobber tells the optimizer that memory may have changed, so the invariant
// kernel cannot be hoisted out of `for (i = 0; i < repeat; i++)`. The Rust
// reference uses `std::hint::black_box` for the same purpose; both compilers
// get the same barrier strength, which is what keeps the comparison fair.
static inline void barrier(void) { __asm__ __volatile__("" ::: "memory"); }

// A memory-operand barrier: the value is spilled and reloaded around an empty
// asm, so a computed scalar stays live across the loop boundary.
static inline double keep(double value) {
  double spilled = value;
  __asm__ __volatile__("" : "+m"(spilled) : : "memory");
  return spilled;
}

struct result {
  double sum;
  double sumsq;
  double minimum;
  double maximum;
  uint64_t count_above;
};

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

// The params file has one `key=value` line per parameter (protocol section 5).
static double read_threshold(const char* path) {
  FILE* file = fopen(path, "r");
  if (file == NULL) {
    fail_path("cannot read", path);
  }
  char line[4096];
  while (fgets(line, sizeof line, file) != NULL) {
    if (strncmp(line, "threshold=", 10) == 0) {
      char* value = line + 10;
      value[strcspn(value, "\r\n")] = '\0';
      char* end = NULL;
      errno = 0;
      double threshold = strtod(value, &end);
      if (end == value || *end != '\0' || errno != 0) {
        fclose(file);
        fail("threshold must be a number");
      }
      fclose(file);
      return threshold;
    }
  }
  fclose(file);
  fail("params: missing threshold");
  return 0.0;
}

// Portable little-endian load: the dataset is byte-identical for every
// implementation regardless of the host's byte order.
static double load_f64_le(const unsigned char* bytes) {
  uint64_t bits = 0;
  for (int offset = 0; offset < 8; offset++) {
    bits |= (uint64_t)bytes[offset] << (8 * offset);
  }
  double value;
  memcpy(&value, &bits, sizeof value);
  return value;
}

static struct result scan(const double* values, size_t count, double threshold) {
  struct result result;
  result.sum = 0.0;
  result.sumsq = 0.0;
  result.minimum = INFINITY;
  result.maximum = -INFINITY;
  result.count_above = 0;
  for (size_t index = 0; index < count; index++) {
    double value = values[index];
    result.sum += value;
    result.sumsq += value * value;
    if (value < result.minimum) {
      result.minimum = value;
    }
    if (value > result.maximum) {
      result.maximum = value;
    }
    if (value > threshold) {
      result.count_above += 1;
    }
  }
  return result;
}

// JSON has one number type; the protocol asks floats to stay floats, so an
// integral double is printed as `1.0` and never as `1`. `%.17g` round-trips.
static void print_double(FILE* out, double value) {
  if (!isfinite(value)) {
    fail("output value is not finite");
  }
  char text[64];
  snprintf(text, sizeof text, "%.17g", value);
  if (strpbrk(text, ".eE") == NULL) {
    strcat(text, ".0");
  }
  fputs(text, out);
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
  const char* params = option(argc, argv, "--params");
  const char* output = option(argc, argv, "--output");
  const char* repeat_text = option(argc, argv, "--repeat");

  char* repeat_end = NULL;
  unsigned long long repeat = strtoull(repeat_text, &repeat_end, 10);
  if (repeat_end == repeat_text || *repeat_end != '\0') {
    fail("--repeat must be a non-negative integer");
  }

  double threshold = read_threshold(params);

  size_t length = 0;
  unsigned char* bytes = read_file(input, &length);
  if (length % 8 != 0) {
    fprintf(stderr, "dataset size %zu is not a multiple of 8\n", length);
    exit(2);
  }
  size_t count = length / 8;
  double* values = malloc(count * sizeof(double) + 1);
  if (values == NULL) {
    fail("out of memory");
  }
  for (size_t index = 0; index < count; index++) {
    values[index] = load_f64_le(bytes + index * 8);
  }
  free(bytes);

  struct result result = {0.0, 0.0, 0.0, 0.0, 0};
  for (unsigned long long iteration = 0; iteration < repeat; iteration++) {
    // Same threshold on every iteration, but the barrier keeps the compiler
    // from lifting the invariant kernel out of the loop.
    double iteration_threshold = keep(threshold);
    barrier();
    result = scan(values, count, iteration_threshold);
    result.sum = keep(result.sum);
    result.sumsq = keep(result.sumsq);
    result.minimum = keep(result.minimum);
    result.maximum = keep(result.maximum);
  }

  FILE* file = fopen(output, "w");
  if (file == NULL) {
    fail_path("cannot write", output);
  }
  fprintf(file, "{\n  \"n\": %zu,\n  \"sum\": ", count);
  print_double(file, result.sum);
  fputs(",\n  \"sumsq\": ", file);
  print_double(file, result.sumsq);
  fputs(",\n  \"min\": ", file);
  print_double(file, result.minimum);
  fputs(",\n  \"max\": ", file);
  print_double(file, result.maximum);
  fprintf(file, ",\n  \"count_above\": %llu\n}\n",
          (unsigned long long)result.count_above);
  if (fclose(file) != 0) {
    fail_path("cannot write", output);
  }
  free(values);
  return 0;
}
