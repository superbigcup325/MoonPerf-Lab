//! gather: the Rust reference implementation.
//!
//! The dataset is a `columnar-gather` stream: `u32 row_count`, then
//! `row_count` × `i64` value, then `row_count` × `u32` index. The kernel
//! gathers the value column through the index vector into an output vector and
//! checksums the result.
//!
//! The generator guarantees every index is in `[0, row_count)`, so the kernel
//! does not run a per-row range check: the question here is the gather loop and
//! its locality, not the cost of an error path.

use std::env;
use std::fs;
use std::hint::black_box;
use std::process;

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

/// One gather pass: indirect read into the output vector, then the checksum.
/// The output vector is allocated and zeroed once before the timed loop and
/// reused for every pass, the way a real operator reuses its batch buffer.
fn gather(values: &[u64], indices: &[u32], out: &mut [u64]) -> u64 {
    let rows = indices.len();
    for row in 0..rows {
        // Safe: the dataset generator guarantees 0 <= index < rows.
        out[row] = unsafe { *values.get_unchecked(indices[row] as usize) };
    }
    let mut checksum = 0u64;
    for row in 0..rows {
        checksum = checksum.wrapping_add(out[row].wrapping_mul(row as u64 + 1));
    }
    checksum
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
    if bytes.len() < 4 {
        fail("dataset is shorter than its header");
    }
    let mut header = [0u8; 4];
    header.copy_from_slice(&bytes[..4]);
    let rows = u32::from_le_bytes(header) as usize;
    let expected = 4 + rows * 8 + rows * 4;
    if bytes.len() != expected {
        fail(&format!(
            "dataset size {} does not match {rows} rows ({expected} bytes)",
            bytes.len()
        ));
    }

    // Materialize the two columns once, before the timed loop.
    let values_start = 4;
    let indices_start = values_start + rows * 8;
    let mut values = vec![0u64; rows];
    for row in 0..rows {
        let mut word = [0u8; 8];
        word.copy_from_slice(&bytes[values_start + row * 8..values_start + row * 8 + 8]);
        values[row] = u64::from_le_bytes(word);
    }
    let mut indices = vec![0u32; rows];
    for row in 0..rows {
        let mut word = [0u8; 4];
        word.copy_from_slice(&bytes[indices_start + row * 4..indices_start + row * 4 + 4]);
        indices[row] = u32::from_le_bytes(word);
    }

    let mut out = vec![0u64; rows];
    let mut checksum = 0u64;
    for _ in 0..repeat {
        checksum = gather(&values, &indices, &mut out);
        checksum = black_box(checksum);
    }

    let text = format!(
        "{{\n  \"rows\": {rows},\n  \"checksum\": \"{checksum:016x}\"\n}}\n"
    );
    fs::write(&output, text).unwrap_or_else(|error| {
        fail(&format!("cannot write {output}: {error}"));
    });
}
