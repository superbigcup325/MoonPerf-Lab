//! numeric-scan: the Rust reference implementation.
//!
//! One sequential pass over an `f64` slice accumulating sum, sum of squares,
//! min, max and the number of values above a threshold. The adapter contract
//! (protocol section 5) passes the dataset, the params file, the output path
//! and the inner repeat count on the command line.

use std::env;
use std::fs;
use std::process;

struct Args {
    input: String,
    params: String,
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

fn read_threshold(path: &str) -> f64 {
    let text = fs::read_to_string(path).unwrap_or_else(|error| {
        eprintln!("cannot read {path}: {error}");
        process::exit(2);
    });
    for line in text.lines() {
        if let Some(value) = line.strip_prefix("threshold=") {
            return value.parse().unwrap_or_else(|error| {
                eprintln!("threshold must be a number: {error}");
                process::exit(2);
            });
        }
    }
    eprintln!("params: missing threshold");
    process::exit(2);
}

fn scan(data: &[f64], threshold: f64) -> (f64, f64, f64, f64, usize) {
    let mut sum = 0.0f64;
    let mut sumsq = 0.0f64;
    let mut minimum = f64::INFINITY;
    let mut maximum = f64::NEG_INFINITY;
    let mut count_above = 0usize;
    for &value in data {
        sum += value;
        sumsq += value * value;
        if value < minimum {
            minimum = value;
        }
        if value > maximum {
            maximum = value;
        }
        if value > threshold {
            count_above += 1;
        }
    }
    (sum, sumsq, minimum, maximum, count_above)
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let parsed = Args {
        input: option(&args, "--input"),
        params: option(&args, "--params"),
        output: option(&args, "--output"),
        repeat: option(&args, "--repeat").parse().unwrap_or_else(|error| {
            eprintln!("--repeat must be a positive integer: {error}");
            process::exit(2);
        }),
    };

    let threshold = read_threshold(&parsed.params);
    let bytes = fs::read(&parsed.input).unwrap_or_else(|error| {
        eprintln!("cannot read {}: {error}", parsed.input);
        process::exit(2);
    });
    if bytes.len() % 8 != 0 {
        eprintln!("dataset size {} is not a multiple of 8", bytes.len());
        process::exit(2);
    }
    let data: Vec<f64> = bytes
        .chunks_exact(8)
        .map(|chunk| f64::from_le_bytes(chunk.try_into().expect("chunk size")))
        .collect();

    let mut result = (0.0, 0.0, 0.0, 0.0, 0);
    for _ in 0..parsed.repeat {
        result = scan(&data, threshold);
    }

    // `{:?}` prints a round-trippable float and keeps an integral value as
    // `1.0`, so the JSON type stays a number (protocol section 5).
    let text = format!(
        "{{\n  \"n\": {},\n  \"sum\": {:?},\n  \"sumsq\": {:?},\n  \"min\": {:?},\n  \"max\": {:?},\n  \"count_above\": {}\n}}\n",
        data.len(),
        result.0,
        result.1,
        result.2,
        result.3,
        result.4,
    );
    fs::write(&parsed.output, text).unwrap_or_else(|error| {
        eprintln!("cannot write {}: {error}", parsed.output);
        process::exit(2);
    });
}
