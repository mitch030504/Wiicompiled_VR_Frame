// The AX mix kernels' vector forms (AVX2 on x86-64, NEON on arm64) must be bit-exact with the
// scalar reference loops they replace. Random blocks at every tail length, plus the ramp and
// clamp extremes; on a build with neither vector form this compares the scalar loops with
// themselves.

#include "../src/hle/audio/ax_mix_kernels.h"

#include <cstdint>
#include <cstring>
#include <iostream>
#include <random>
#include <vector>

namespace {

int g_failures = 0;

void Fail(const char* kernel, uint32_t count, uint32_t volume, uint32_t delta) {
    if (++g_failures <= 10) {
        std::cerr << kernel << " differs from the scalar loop: count " << count << ", volume "
                  << volume << ", delta " << delta << '\n';
    }
}

template <typename T>
std::vector<T> RandomBlock(std::mt19937& rng, uint32_t count, int64_t low, int64_t high) {
    std::uniform_int_distribution<int64_t> dist(low, high);
    std::vector<T> block(count);
    for (auto& value : block) {
        value = static_cast<T>(dist(rng));
    }
    return block;
}

void CheckRamps(std::mt19937& rng, uint32_t count, uint16_t volume, uint16_t delta) {
    const auto input = RandomBlock<int16_t>(rng, count, INT16_MIN, INT16_MAX);
    const auto bus = RandomBlock<int32_t>(rng, count, -(1 << 24), 1 << 24);

    auto expectedOut = bus;
    auto actualOut = bus;
    int16_t expectedDpop = 1234;
    int16_t actualDpop = 1234;
    const uint16_t expectedVolume =
        AxMixKernels::MixAddRampScalar(expectedOut.data(), input.data(), count, volume, delta, expectedDpop);
    const uint16_t actualVolume =
        AxMixKernels::MixAddRamp(actualOut.data(), input.data(), count, volume, delta, actualDpop);
    if (expectedOut != actualOut || expectedDpop != actualDpop || expectedVolume != actualVolume) {
        Fail("MixAddRamp", count, volume, delta);
    }

    auto expectedSamples = input;
    auto actualSamples = input;
    const uint16_t expectedScaled = AxMixKernels::ScaleRampScalar(expectedSamples.data(), count, volume, delta);
    const uint16_t actualScaled = AxMixKernels::ScaleRamp(actualSamples.data(), count, volume, delta);
    if (expectedSamples != actualSamples || expectedScaled != actualScaled) {
        Fail("ScaleRamp", count, volume, delta);
    }
}

void CheckAccumAndMarshal(std::mt19937& rng, uint32_t count) {
    const auto src = RandomBlock<int32_t>(rng, count, INT32_MIN, INT32_MAX);
    const auto ramp = RandomBlock<uint16_t>(rng, count, 0, UINT16_MAX);
    const auto bus = RandomBlock<int32_t>(rng, count, -(1 << 24), 1 << 24);
    auto expected = bus;
    auto actual = bus;
    AxMixKernels::MixAccumRamp32Scalar(expected.data(), src.data(), ramp.data(), count);
    AxMixKernels::MixAccumRamp32(actual.data(), src.data(), ramp.data(), count);
    if (expected != actual) {
        Fail("MixAccumRamp32", count, 0, 0);
    }

    std::vector<uint8_t> expectedBytes(count * 4);
    std::vector<uint8_t> actualBytes(count * 4);
    AxMixKernels::StoreBigEndian32Scalar(expectedBytes.data(), src.data(), count);
    AxMixKernels::StoreBigEndian32(actualBytes.data(), src.data(), count);
    if (expectedBytes != actualBytes) {
        Fail("StoreBigEndian32", count, 0, 0);
    }

    std::vector<int32_t> expectedWords(count);
    std::vector<int32_t> actualWords(count);
    AxMixKernels::LoadBigEndian32Scalar(expectedWords.data(), expectedBytes.data(), count);
    AxMixKernels::LoadBigEndian32(actualWords.data(), expectedBytes.data(), count);
    if (expectedWords != actualWords || expectedWords != src) {
        Fail("LoadBigEndian32", count, 0, 0);
    }
}

} // namespace

int main() {
    std::mt19937 rng(0x41584D58u);
    std::uniform_int_distribution<uint32_t> any16(0, UINT16_MAX);
    const uint16_t edges[] = {0, 1, 0x7FFF, 0x8000, 0x8001, 0xFFFE, 0xFFFF};

    // Every tail length around the vector widths, and the AX frame sizes (96 per 3 ms frame,
    // 160 at the 5 ms subframe the AXWii list can use).
    for (uint32_t count = 0; count <= 40; ++count) {
        for (uint16_t volume : edges) {
            for (uint16_t delta : edges) {
                CheckRamps(rng, count, volume, delta);
            }
        }
        for (int trial = 0; trial < 64; ++trial) {
            CheckRamps(rng, count, static_cast<uint16_t>(any16(rng)), static_cast<uint16_t>(any16(rng)));
        }
        CheckAccumAndMarshal(rng, count);
    }
    for (uint32_t count : {96u, 160u, 255u}) {
        for (int trial = 0; trial < 256; ++trial) {
            CheckRamps(rng, count, static_cast<uint16_t>(any16(rng)), static_cast<uint16_t>(any16(rng)));
            CheckAccumAndMarshal(rng, count);
        }
    }

    if (g_failures != 0) {
        std::cerr << g_failures << " mismatches\n";
        return 1;
    }
    std::cout << "ax mix kernels match the scalar loops (avx2 " << MKW_AX_MIX_AVX2 << ", neon "
              << MKW_AX_MIX_NEON << ")\n";
    return 0;
}
