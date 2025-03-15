use std::ops::RangeInclusive;

fn srgb2linear(x: u8) -> f32 {
    let x = x as f32 / 255.0;
    if x <= 0.04045 {
        x * 0.07739938 // 1.0/12.92
    } else {
        ((x + 0.055) / 1.055).powf(2.4)
    }
}

fn linear2srgb(x: f32) -> u8 {
    let x = if x <= 0.0031308 {
        x * 12.92
    } else {
        1.055 * x.powf(1.0 / 2.4) - 0.055
    };
    (x * 255.0 + 0.5) as u8
}

// function automatic [7:0] correct_gamma22;
//     input [7:0] color;
//     if      (color == 0)
//         correct_gamma22 = 0;
//     else if (color <= 11)
//         correct_gamma22 = (color << 2) + 20;
//     else if (color <= 40)
//         correct_gamma22 = (color << 1) + 35;
//     else if (color <= 113)
//         correct_gamma22 = (color     ) + 70;
//     else
//         correct_gamma22 = (color >> 1) + 125;
// endfunction
fn correct_gamma22(color: i16) -> u8 {
    (if color == 0 {
        0
    } else if color <= 11 {
        (color << 2) + 20
    } else if color <= 40 {
        (color << 1) + 35
    } else if color <= 113 {
        color + 70
    } else {
        (color >> 1) + 125
    }) as u8
}

#[derive(Debug, Default, Clone, Copy)]
struct Term {
    lsh: u16,
    rsh: u16,
    add: bool,
}

impl Term {
    #[inline]
    fn calc(&self, input: i64) -> i64 {
        let res = (input << self.lsh as i64) >> self.rsh as i64;
        if self.add {
            res
        } else {
            -res
        }
    }
}

#[derive(Debug, Default, Clone, Copy)]
struct ShiftAdd {
    br: u16,
    terms: [Term; 3],
    add: i16,
}

impl ShiftAdd {
    #[inline]
    fn calc(&self, input: i64) -> i64 {
        let mut res = 0;
        for term in self.terms.iter() {
            res += term.calc(input);
        }
        res += self.add as i64;
        res
    }

    fn print(&self) {
        let terms = self.terms.map(|term| {
            let add_sub = if term.add { "+" } else { "-" };
            if term.lsh > 0 {
                format!("{} (color << {})", add_sub, term.lsh)
            } else {
                format!("{} (color >> {})", add_sub, term.rsh)
            }
        });

        println!(
            "if color <= {} {{ return {} {} {} + {}; }}",
            self.br, terms[0], terms[1], terms[2], self.add
        );
    }
}

fn find_shift_add(range: RangeInclusive<u16>, lut: &[u8; 512]) -> ShiftAdd {
    let mut min_values = ShiftAdd::default();
    let mut min_error = f32::MAX;

    for i in 0..=18 {
        for a0 in [true, false] {
            let lshift0 = if i <= 9 { 9 - i } else { 0 };
            let rshift0 = if i > 9 { i - 9 } else { 0 };
            let term0 = Term {
                lsh: lshift0,
                rsh: rshift0,
                add: a0,
            };

            for j in 0..=18 {
                if i == j {
                    continue;
                }
                for a1 in [true, false] {
                    let lshift1 = if j <= 9 { 9 - j } else { 0 };
                    let rshift1 = if j > 9 { j - 9 } else { 0 };
                    let term1 = Term {
                        lsh: lshift1,
                        rsh: rshift1,
                        add: a1,
                    };

                    for k in 0..=18 {
                        if i == k || j == k {
                            continue;
                        }
                        for a2 in [true, false] {
                            let lshift2 = if k <= 9 { 9 - k } else { 0 };
                            let rshift2 = if k > 9 { k - 9 } else { 0 };
                            let term2 = Term {
                                lsh: lshift2,
                                rsh: rshift2,
                                add: a2,
                            };
                            let mut shift_add = ShiftAdd {
                                br: *range.end(),
                                terms: [term0, term1, term2],
                                add: 0,
                            };

                            let mut error = 0.0;
                            let mut adds = Vec::new();

                            for input in range.clone() {
                                let input = input as i64;
                                let goal = lut[input as usize] as i64;

                                adds.push(shift_add.calc(input).wrapping_sub(goal));
                            }
                            adds.sort();
                            shift_add.add = if !range.is_empty() {
                                adds[range.len() / 2] as i16
                            } else {
                                0
                            };

                            for input in range.clone() {
                                let input = input as i64;
                                let goal = lut[input as usize] as i64;

                                let diff = shift_add.calc(input).wrapping_sub(goal);

                                error += (diff as f32).powf(2.0);
                            }
                            if !range.is_empty() {
                                error /= range.len() as f32;
                            }
                            if error < min_error {
                                min_error = error;
                                min_values = shift_add;
                            }
                        }
                    }
                }
            }
        }
    }

    min_values
}

fn main() {
    let mut lut = [0u8; 512];

    for (i, val) in lut.iter_mut().enumerate() {
        let x = ((i as f32) / 511.0) + 0.5;
        let y = linear2srgb(x);
        *val = y;
    }

    let mut min_error = f32::MAX;
    let mut min_max_diff = 0;
    let mut best_shift_add0 = ShiftAdd::default();
    let mut best_shift_add1 = ShiftAdd::default();
    let mut best_shift_add2 = ShiftAdd::default();
    let mut best_shift_add3 = ShiftAdd::default();

    for b2 in 200..=300u16 {
        let shift_add2 = find_shift_add(1..=b2, &lut);
        let shift_add3 = find_shift_add(b2..=511, &lut);
        let mut error = 0.0;
        let mut max_diff = 0;
        let mut min_diff = i64::MAX;
        for i in 0..=511 {
            let x = i as f32 / 511.0 + 0.5;
            let y = linear2srgb(x);

            let attempt = if i == 0 {
                0
            } else if i <= b2 {
                shift_add2.calc(i as i64)
            } else {
                shift_add3.calc(i as i64)
            };
            let diff = (attempt - y as i64).abs();
            error += (diff as f32).powf(2.0);
            if diff > max_diff {
                max_diff = diff;
            }
            if diff < min_diff {
                min_diff = diff;
            }
        }
        error /= 512.0;
        if error < min_error {
            min_error = error;
            min_max_diff = max_diff;
            best_shift_add2 = shift_add2;
            best_shift_add3 = shift_add3;
            println!("fn correct_gamma22(color: u8) -> u8 {{");
            best_shift_add2.print();
            best_shift_add3.print();
            println!("0 }}");
            println!(
                "Best error: {} diff: {} -> {}",
                min_error, min_diff, min_max_diff
            );
        }
    }

    println!("fn correct_gamma22(color: u8) -> u8 {{");
    best_shift_add2.print();
    best_shift_add3.print();
    println!("0 }}");
    println!("Best error: {} max diff: {}", min_error, min_max_diff);

    min_error = f32::MAX;
    min_max_diff = 0;

    let fixed_b2 = best_shift_add2.br;

    for b1 in 10..=128u16 {
        println!("b1: {}", b1);
        for b2 in (fixed_b2)..=(fixed_b2 + 30) {
            let shift_add1 = find_shift_add(1..=b1, &lut);
            let shift_add2 = find_shift_add(b1..=b2, &lut);
            let shift_add3 = find_shift_add(b2..=511u16, &lut);

            let mut error = 0.0;
            let mut max_diff = 0;
            let mut min_diff = i64::MAX;
            for i in 0..=511 {
                let x = i as f32 / 511.0 + 0.5;
                let y = linear2srgb(x);

                let attempt = if i == 0 {
                    0
                } else if i <= b1 {
                    shift_add1.calc(i as i64)
                } else if i <= b2 {
                    shift_add2.calc(i as i64)
                } else {
                    shift_add3.calc(i as i64)
                };
                let diff = (attempt - y as i64).abs();
                error += (diff as f32).powf(2.0);
                if diff > max_diff {
                    max_diff = diff;
                }
                if diff < min_diff {
                    min_diff = diff;
                }
            }
            error /= 512.0;
            if error < min_error {
                min_error = error;
                min_max_diff = max_diff;
                best_shift_add1 = shift_add1;
                best_shift_add2 = shift_add2;
                best_shift_add3 = shift_add3;
                println!("fn correct_gamma22(color: u8) -> u8 {{");
                best_shift_add1.print();
                best_shift_add2.print();
                best_shift_add3.print();
                println!("0 }}");
                println!(
                    "Best error: {} diff: {} -> {}",
                    min_error, min_diff, min_max_diff
                );
            }
        }
    }

    println!("fn correct_gamma22(color: u8) -> u8 {{");
    best_shift_add1.print();
    best_shift_add2.print();
    best_shift_add3.print();
    println!("0 }}");
    println!("Best error: {} max diff: {}", min_error, min_max_diff);

    min_error = f32::MAX;
    min_max_diff = 0;

    let fixed_b1 = best_shift_add1.br;
    let fixed_b2 = best_shift_add2.br;

    for b0 in 8..=64u16 {
        for b1 in (fixed_b1)..=(fixed_b1 + 20) {
            println!("b0: {}, b1: {}", b0, b1);
            for b2 in (fixed_b2)..=(fixed_b2 + 30) {
                let shift_add0 = find_shift_add(1..=b0, &lut);
                let shift_add1 = find_shift_add(b0..=b1, &lut);
                let shift_add2 = find_shift_add(b1..=b2, &lut);
                let shift_add3 = find_shift_add(b2..=511u16, &lut);

                let mut error = 0.0;
                let mut max_diff = 0;
                let mut min_diff = i64::MAX;
                for i in 0..=511 {
                    let x = i as f32 / 511.0 + 0.5;
                    let y = linear2srgb(x);

                    let attempt = if i == 0 {
                        0
                    } else if i <= b0 {
                        shift_add0.calc(i as i64)
                    } else if i <= b1 {
                        shift_add1.calc(i as i64)
                    } else if i <= b2 {
                        shift_add2.calc(i as i64)
                    } else {
                        shift_add3.calc(i as i64)
                    };
                    let diff = (attempt - y as i64).abs();
                    error += (diff as f32).powf(2.0);
                    if diff > max_diff {
                        max_diff = diff;
                    }
                    if diff < min_diff {
                        min_diff = diff;
                    }
                }
                error /= 512.0;
                if error < min_error {
                    min_error = error;
                    min_max_diff = max_diff;
                    best_shift_add0 = shift_add0;
                    best_shift_add1 = shift_add1;
                    best_shift_add2 = shift_add2;
                    best_shift_add3 = shift_add3;
                    println!("fn correct_gamma22(color: u8) -> u8 {{");
                    best_shift_add0.print();
                    best_shift_add1.print();
                    best_shift_add2.print();
                    best_shift_add3.print();
                    println!("0 }}");
                    println!(
                        "Best error: {} diff: {} -> {}",
                        min_error, min_diff, min_max_diff
                    );
                }
            }
        }
    }

    println!("fn correct_gamma22(color: u8) -> u8 {{");
    best_shift_add0.print();
    best_shift_add1.print();
    best_shift_add2.print();
    best_shift_add3.print();
    println!("0 }}");
    println!("Best error: {} max diff: {}", min_error, min_max_diff);

    // for i in 0..=255 {
    //     let x = srgb2linear(i);
    //     let il = (x * 511.0 + 0.5) as u16;

    //     let attempt = (il << shift_add.0 >> shift_add.1)
    //         + (il << shift_add.2 >> shift_add.3)
    //         + (il << shift_add.4 >> shift_add.5)
    //         + shift_add.6;
    //     let error = (attempt as i16 - (i >> 1) as i16).abs();

    //     if error > 3 {
    //         shift_add = find_shift_add(i >> 1, il);
    //     }

    //     // let y = linear2srgb(x);-=
    // }

    let adj = 255.0;
    const INBITS: u32 = 256;
    let mut error = 0.0;
    let mut max_diff = 0;
    let mut max_y = 0;
    let mut max_co = 0;
    let mut max_cg = 0;
    let mut min_y = i16::MAX;
    let mut min_co = i16::MAX;
    let mut min_cg = i16::MAX;

    for r in 0..INBITS {
        for g in 0..INBITS {
            for b in 0..INBITS {
                let lr = srgb2linear((r) as u8);
                let lg = srgb2linear((g) as u8);
                let lb = srgb2linear((b) as u8);
                let ilr: i16 = (lr * adj + 0.5) as i16;
                let ilg: i16 = (lg * adj + 0.5) as i16;
                let ilb: i16 = (lb * adj + 0.5) as i16;
                // let ilr: u16 = r as u16;
                // let ilg: u16 = g as u16;
                // let ilb: u16 = b as u16;

                let co = ilr.wrapping_sub(ilb);
                let tmp = ilb.wrapping_add(co >> 1);
                let cg = ilg.wrapping_sub(tmp);
                let y = tmp.wrapping_add(cg >> 1);

                if y > max_y {
                    max_y = y;
                }
                if y < min_y {
                    min_y = y;
                }
                if co > max_co {
                    max_co = co;
                }
                if co < min_co {
                    min_co = co;
                }
                if cg > max_cg {
                    max_cg = cg;
                }
                if cg < min_cg {
                    min_cg = cg;
                }

                //let yg = linear2srgb((y as f32 / adj).clamp(0.0, 1.0)) as u16;

                let tmp = y.wrapping_sub(cg >> 1);
                let g2 = cg.wrapping_add(tmp);
                let b2 = tmp.wrapping_sub(co >> 1);
                let r2 = b2.wrapping_add(co);

                // let r2 = linear2srgb((r2 as f32 / adj).clamp(0.0, 1.0));
                // let g2 = linear2srgb((g2 as f32 / adj).clamp(0.0, 1.0));
                // let b2 = linear2srgb((b2 as f32 / adj).clamp(0.0, 1.0));
                let r2 = correct_gamma22(r2);
                let g2 = correct_gamma22(g2);
                let b2 = correct_gamma22(b2);

                error += ((r as f64 - r2 as f64).powf(2.0)
                    + (g as f64 - g2 as f64).powf(2.0)
                    + (b as f64 - b2 as f64).powf(2.0))
                    / 3.0;
                if (r as i32 - r2 as i32).abs() > max_diff {
                    max_diff = (r as i32 - r2 as i32).abs();
                }
                if (g as i32 - g2 as i32).abs() > max_diff {
                    max_diff = (g as i32 - g2 as i32).abs();
                }
                if (b as i32 - b2 as i32).abs() > max_diff {
                    max_diff = (b as i32 - b2 as i32).abs();
                }
            }
        }
    }
    println!(
        "Error: {} diff: {} y: {}-{} co: {}-{}, cg: {}-{}",
        error / 256.0_f64.powf(3.0),
        max_diff,
        min_y,
        max_y,
        min_co,
        max_co,
        min_cg,
        max_cg
    );
}
