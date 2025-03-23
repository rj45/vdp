use std::simd::num::SimdFloat;
use std::simd::{LaneCount, Simd, StdFloat, SupportedLaneCount};

use kmeans::DistanceFunction;
use serde::{Deserialize, Serialize};

#[derive(Copy, Clone, Debug, PartialOrd, PartialEq)]
#[repr(transparent)]
pub struct Oklab(oklab::Oklab);

impl Serialize for Oklab {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        (self.0.l, self.0.a, self.0.b).serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for Oklab {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let (l, a, b) = Deserialize::deserialize(deserializer)?;
        Ok(Oklab(oklab::Oklab { l, a, b }))
    }
}

impl std::ops::Deref for Oklab {
    type Target = oklab::Oklab;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl std::ops::DerefMut for Oklab {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl From<oklab::Oklab> for Oklab {
    fn from(oklab: oklab::Oklab) -> Self {
        Oklab(oklab)
    }
}

impl Oklab {
    pub fn new(l: f32, a: f32, b: f32) -> Self {
        Oklab(oklab::Oklab { l, a, b })
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct ColorFrequency {
    pub color: Oklab,
    pub frequency: usize,
}

impl Default for ColorFrequency {
    fn default() -> Self {
        ColorFrequency {
            color: Oklab::new(0.0, 0.0, 0.0),
            frequency: 0,
        }
    }
}

/// Calculate the perceptual difference between two colors in Oklab space
pub fn oklab_delta_e(a: Oklab, b: Oklab) -> f32 {
    // ΔL = L1 - L2
    // C1 = √(a1² + b1²)
    // C2 = √(a2² + b2²)
    // ΔC = C1 - C2
    // Δa = a1 - a2
    // Δb = b1 - b2
    // ΔH = √(|Δa² + Δb² - ΔC²|)
    // ΔEOK = √(ΔL² + ΔC² + ΔH²)
    let delta_l = a.l - b.l;
    let c1 = (a.a * a.a + a.b * a.b).sqrt();
    let c2 = (b.a * b.a + b.b * b.b).sqrt();
    let delta_c = c1 - c2;
    let delta_a = a.a - b.a;
    let delta_b = a.b - b.b;
    let delta_h = (delta_a * delta_a + delta_b * delta_b - delta_c * delta_c)
        .abs()
        .sqrt();
    (delta_l * delta_l + delta_c * delta_c + delta_h * delta_h).sqrt()
}

pub struct OklabDistance;

impl<const LANES: usize> DistanceFunction<f32, LANES> for OklabDistance
where
    LaneCount<LANES>: SupportedLaneCount,
{
    #[inline(always)]
    fn distance(&self, a: &[f32], b: &[f32]) -> f32 {
        let a_len = a.len() / 3;
        let b_len = b.len() / 3;

        let a_l = a[0..a_len].chunks_exact(LANES).map(|i| Simd::from_slice(i));
        let a_a = a[a_len..2 * a_len]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));
        let a_b = a[2 * a_len..]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));

        let b_l = b[0..b_len].chunks_exact(LANES).map(|i| Simd::from_slice(i));
        let b_a = b[b_len..2 * b_len]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));
        let b_b = b[2 * b_len..]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));

        // ΔL = L1 - L2
        // C1 = √(a1² + b1²)
        // C2 = √(a2² + b2²)
        // ΔC = C1 - C2
        // Δa = a1 - a2
        // Δb = b1 - b2
        // ΔH = √(|Δa² + Δb² - ΔC²|)
        // ΔEOK = √(ΔL² + ΔC² + ΔH²)

        let delta_l = a_l.zip(b_l).map(|(a_l, b_l)| a_l - b_l);
        let c1 = a_a
            .clone()
            .zip(a_b.clone())
            .map(|(a_a, a_b)| (a_a * a_a + a_b * a_b).sqrt());
        let c2 = b_a
            .clone()
            .zip(b_b.clone())
            .map(|(b_a, b_b)| (b_a * b_a + b_b * b_b).sqrt());
        let delta_c = c1.zip(c2).map(|(c1, c2)| c1 - c2);
        let delta_a = a_a.zip(b_a).map(|(a_a, b_a)| a_a - b_a);
        let delta_b = a_b.zip(b_b).map(|(a_b, b_b)| a_b - b_b);
        let sum_delta_a_b = delta_a
            .zip(delta_b)
            .map(|(delta_a, delta_b)| delta_a * delta_a + delta_b * delta_b);
        let delta_h = sum_delta_a_b
            .zip(delta_c.clone())
            .map(|(sum_delta_a_b, delta_c)| (sum_delta_a_b - delta_c * delta_c).abs().sqrt());
        let sum_delta_l_c = delta_l
            .zip(delta_c)
            .map(|(delta_l, delta_c)| delta_l * delta_l + delta_c * delta_c);
        let delta_e = sum_delta_l_c
            .zip(delta_h)
            .map(|(sum_delta_l_c, delta_h)| (sum_delta_l_c + delta_h * delta_h).sqrt());
        delta_e.map(|e| e.reduce_sum()).sum()
    }
}
