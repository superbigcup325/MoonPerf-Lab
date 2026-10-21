//! sql-groupby: the Rust reference implementation.
//!
//! The dataset is a `csv-records` file: `id,category,amount` and one row per
//! record. The kernel parses the CSV and answers one fixed query:
//!
//!   SELECT category, count(*) AS n, sum(amount) AS total
//!   FROM t GROUP BY category ORDER BY category
//!
//! and folds the result into a checksum: for output row `i`, add
//! `n * (i + 1) + total` to a wrapping 64-bit accumulator. The query is fixed,
//! so a hand-written pipeline and a SQL engine answer the same question; the
//! workload README says what each one is.

use std::env;
use std::fs;
use std::hint::black_box;
use std::process;

struct Result {
    groups: u64,
    rows: u64,
    checksum: u64,
}

fn option(args: &[String], name: &str) -> String {
    let mut index = 0;
    while index + 1 < args.len() {
        if args[index] == name {
            return args[index + 1].clone();
        }
        index += 1;
    }
    eprintln!("missing option {name}");
    process::exit(2);
}

fn fail(message: &str) -> ! {
    eprintln!("{message}");
    process::exit(2);
}

/// Parse one decimal integer, stopping at a delimiter.
fn parse_number(bytes: &[u8], cursor: &mut usize) -> u64 {
    let mut value = 0u64;
    let mut digits = 0;
    while *cursor < bytes.len() {
        let byte = bytes[*cursor];
        if byte.is_ascii_digit() {
            value = value * 10 + (byte - b'0') as u64;
            digits += 1;
            *cursor += 1;
        } else {
            break;
        }
    }
    if digits == 0 {
        fail("csv: expected a decimal integer");
    }
    value
}

const CATEGORIES: usize = 4096;

fn query(bytes: &[u8]) -> Result {
    let mut counts = [0u64; CATEGORIES];
    let mut totals = [0u64; CATEGORIES];
    let mut rows = 0u64;
    let mut cursor = 0usize;

    // Header: skip to the first newline.
    while cursor < bytes.len() && bytes[cursor] != b'\n' {
        cursor += 1;
    }
    if cursor < bytes.len() {
        cursor += 1;
    }

    while cursor < bytes.len() {
        let _id = parse_number(bytes, &mut cursor);
        if cursor >= bytes.len() || bytes[cursor] != b',' {
            fail("csv: expected ',' after id");
        }
        cursor += 1;
        let category = parse_number(bytes, &mut cursor);
        if cursor >= bytes.len() || bytes[cursor] != b',' {
            fail("csv: expected ',' after category");
        }
        cursor += 1;
        let amount = parse_number(bytes, &mut cursor);
        if cursor < bytes.len() && bytes[cursor] == b'\r' {
            cursor += 1;
        }
        if cursor < bytes.len() && bytes[cursor] == b'\n' {
            cursor += 1;
        }
        let slot = category as usize;
        if slot >= CATEGORIES {
            fail("csv: category out of the declared range");
        }
        counts[slot] += 1;
        totals[slot] += amount;
        rows += 1;
    }

    let mut groups = 0u64;
    let mut checksum = 0u64;
    for slot in 0..CATEGORIES {
        if counts[slot] == 0 {
            continue;
        }
        groups += 1;
        checksum = checksum.wrapping_add(counts[slot].wrapping_mul(groups));
        checksum = checksum.wrapping_add(totals[slot]);
    }
    Result { groups, rows, checksum }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let input = option(&args, "--input");
    let output = option(&args, "--output");
    let repeat: usize = option(&args, "--repeat").parse().unwrap_or_else(|error| {
        eprintln!("--repeat must be a non-negative integer: {error}");
        process::exit(2);
    });
    // The contract passes --params even when the workload declares none.
    let _ = option(&args, "--params");

    let bytes = fs::read(&input).unwrap_or_else(|error| {
        fail(&format!("cannot read {input}: {error}"));
    });

    let mut result = Result { groups: 0, rows: 0, checksum: 0 };
    for _ in 0..repeat {
        result = query(&bytes);
        result.checksum = black_box(result.checksum);
        result.groups = black_box(result.groups);
    }

    let text = format!(
        "{{\n  \"groups\": {},\n  \"rows\": {},\n  \"checksum\": \"{:016x}\"\n}}\n",
        result.groups, result.rows, result.checksum
    );
    fs::write(&output, text).unwrap_or_else(|error| {
        fail(&format!("cannot write {output}: {error}"));
    });
}
