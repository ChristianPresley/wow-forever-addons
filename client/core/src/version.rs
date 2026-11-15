//! Version comparison for addon versions such as "1.2.3" or "v12.9.0-beta".

use std::cmp::Ordering;

fn parts(version: &str) -> Vec<u64> {
    let trimmed = version.trim();
    let trimmed = trimmed.strip_prefix(['v', 'V']).unwrap_or(trimmed);
    let main = trimmed.split(['-', '+']).next().unwrap_or("");
    main.split('.')
        .map(|part| {
            let digits: String = part.chars().take_while(char::is_ascii_digit).collect();
            digits.parse().unwrap_or(0)
        })
        .collect()
}

/// `Less` if `a` is older than `b`. Missing parts count as zero, so "1.0" equals "1.0.0".
pub fn compare_versions(a: &str, b: &str) -> Ordering {
    let (pa, pb) = (parts(a), parts(b));
    for i in 0..pa.len().max(pb.len()) {
        let ordering = pa.get(i).unwrap_or(&0).cmp(pb.get(i).unwrap_or(&0));
        if ordering != Ordering::Equal {
            return ordering;
        }
    }
    Ordering::Equal
}
