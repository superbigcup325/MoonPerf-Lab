//! hash-join: the Rust reference implementation.
//!
//! The dataset is one `structured-records` stream (16-byte records: a `u64` key
//! and a `u64` payload). The first half of the records is the build side, the
//! second half is the probe side. The kernel builds a chained hash table over
//! the build side, probes it with every probe row, and counts the matching
//! (build, probe) pairs plus a wrapping checksum of their payloads.
//!
//! The checksum is a pure function of the data: `sum(build_payload +
//! probe_payload)` over every matching pair, modulo 2^64. It does not depend on
//! the table shape or the traversal order, so the implementations are free to
//! choose their own table while still producing the same output.

use std::env;
use std::fs;
use std::hint::black_box;
use std::process;

const GAMMA: u64 = 0x9E37_79B9_7F4A_7C15;
const EMPTY: u64 = u64::MAX;
const RECORD_BYTES: usize = 16;

struct Args {
    input: String,
    output: String,
    repeat: usize,
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

fn slot_of(key: u64, mask: u64) -> usize {
    (key.wrapping_mul(GAMMA) >> 32) as usize & mask as usize
}

/// One join pass: build the table, probe it, return (pairs, checksum).
fn join(data: &[u64], rows: usize, build_rows: usize) -> (u64, u64) {
    let table_size = (build_rows * 2).next_power_of_two().max(16);
    let mut heads = vec![EMPTY; table_size];
    let mut next = vec![EMPTY; build_rows];
    // Insert is O(1): a collision only extends the chain, and the probe side
    // compares keys while walking it.
    for row in 0..build_rows {
        let key = data[row * 2];
        let slot = slot_of(key, table_size as u64 - 1);
        next[row] = heads[slot];
        heads[slot] = row as u64;
    }
    let mut pairs = 0u64;
    let mut checksum = 0u64;
    for row in build_rows..rows {
        let key = data[row * 2];
        let payload = data[row * 2 + 1];
        let slot = slot_of(key, table_size as u64 - 1);
        let mut cursor = heads[slot];
        while cursor != EMPTY {
            let build = cursor as usize;
            if data[build * 2] == key {
                pairs += 1;
                checksum = checksum
                    .wrapping_add(data[build * 2 + 1])
                    .wrapping_add(payload);
            }
            cursor = next[build];
        }
    }
    (pairs, checksum)
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let parsed = Args {
        input: option(&args, "--input"),
        output: option(&args, "--output"),
        repeat: option(&args, "--repeat").parse().unwrap_or_else(|error| {
            eprintln!("--repeat must be a non-negative integer: {error}");
            process::exit(2);
        }),
    };
    // The contract passes --params even when the workload declares none; the
    // file exists and is empty, and this kernel needs no parameter from it.
    let _ = option(&args, "--params");

    let bytes = fs::read(&parsed.input).unwrap_or_else(|error| {
        fail(&format!("cannot read {}: {error}", parsed.input));
    });
    if bytes.len() % RECORD_BYTES != 0 {
        fail(&format!(
            "dataset size {} is not a multiple of {RECORD_BYTES}",
            bytes.len()
        ));
    }
    let rows = bytes.len() / RECORD_BYTES;
    if rows == 0 || rows % 2 != 0 {
        fail("the dataset must contain a positive even number of records");
    }
    let build_rows = rows / 2;

    // Materialize the records once, before the timed loop.
    let mut data: Vec<u64> = Vec::with_capacity(rows * 2);
    for chunk in bytes.chunks_exact(8) {
        let mut word = [0u8; 8];
        word.copy_from_slice(chunk);
        data.push(u64::from_le_bytes(word));
    }

    let mut result = (0u64, 0u64);
    for _ in 0..parsed.repeat {
        result = join(&data, rows, build_rows);
        result = black_box(result);
    }

    let text = format!(
        "{{\n  \"build_rows\": {build_rows},\n  \"probe_rows\": {},\n  \"pairs\": {},\n  \"checksum\": \"{:016x}\"\n}}\n",
        rows - build_rows,
        result.0,
        result.1,
    );
    fs::write(&parsed.output, text).unwrap_or_else(|error| {
        fail(&format!("cannot write {}: {error}", parsed.output));
    });
}
