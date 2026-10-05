#include "gfx/foveation.hpp"

#include <gtest/gtest.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>
#include <vector>

namespace aurora::gfx::foveation {
namespace {

constexpr float kDegrees = 3.14159265358979f / 180.0f;

// Roughly a Quest 3 left eye: the wider side is the outer (left) one.
EyeFov left_eye() {
  return EyeFov{.tanLeft = std::tan(-54.0f * kDegrees),
                .tanRight = std::tan(43.0f * kDegrees),
                .tanDown = std::tan(-50.0f * kDegrees),
                .tanUp = std::tan(47.0f * kDegrees)};
}

EyeFov right_eye() {
  const EyeFov left = left_eye();
  return EyeFov{.tanLeft = -left.tanRight, .tanRight = -left.tanLeft, .tanDown = left.tanDown, .tanUp = left.tanUp};
}

Map build_map(Level level, const EyeFov& fov = left_eye(), uint32_t width = 1344, uint32_t height = 1408,
              uint32_t texel = 32) {
  Map map;
  foveation::build(width, height, texel, fov, level, map);
  return map;
}

uint8_t at(const Map& map, uint32_t x, uint32_t y) { return map.rg8[(static_cast<size_t>(y) * map.width + x) * 2]; }

// The tangents at a texel centre, as build computes them.
std::pair<float, float> tangents(const Map& map, const EyeFov& fov, uint32_t x, uint32_t y, uint32_t width,
                                 uint32_t height, uint32_t texel) {
  const float u = std::min((x + 0.5f) * texel, static_cast<float>(width)) / width;
  const float v = std::min((y + 0.5f) * texel, static_cast<float>(height)) / height;
  return {fov.tanLeft + (fov.tanRight - fov.tanLeft) * u, fov.tanUp + (fov.tanDown - fov.tanUp) * v};
}

TEST(Foveation, MapCoversTheWholeEye) {
  const Map quest = build_map(Level::Medium);
  EXPECT_EQ(quest.width, 42u);
  EXPECT_EQ(quest.height, 44u);
  EXPECT_EQ(quest.rg8.size(), 42u * 44u * 2u);

  // render_scale 0.75: the last column and row overhang the eye.
  const Map scaled = build_map(Level::Medium, left_eye(), 1260, 1320);
  EXPECT_EQ(scaled.width, 40u);
  EXPECT_EQ(scaled.height, 42u);
}

TEST(Foveation, WritesOnlyWholeHalfAndQuarterDensities) {
  for (Level level : {Level::Low, Level::Medium, Level::High}) {
    const Map map = build_map(level);
    for (size_t i = 0; i < map.rg8.size(); i += 2) {
      const uint8_t value = map.rg8[i];
      EXPECT_TRUE(value == kFullDensity || value == kHalfDensity || value == kQuarterDensity) << int(value);
      // The same density in both directions.
      EXPECT_EQ(map.rg8[i], map.rg8[i + 1]);
    }
  }
  // A half must stay below 1/2 so the fragment size cannot round down to a single pixel.
  EXPECT_LE(kHalfDensity / 255.0f, 0.5f);
  EXPECT_LE(kQuarterDensity / 255.0f, 0.25f);
  EXPECT_GT(kHalfDensity / 255.0f, 0.25f);
}

TEST(Foveation, OffShadesEverythingFully) {
  const Map map = build_map(Level::Off);
  EXPECT_TRUE(std::all_of(map.rg8.begin(), map.rg8.end(), [](uint8_t value) { return value == kFullDensity; }));
}

TEST(Foveation, DensityNeverRisesAwayFromTheForwardDirection) {
  const EyeFov fov = left_eye();
  for (Level level : {Level::Low, Level::Medium, Level::High}) {
    const Map map = build_map(level, fov);
    std::vector<std::pair<float, uint8_t>> texels;
    for (uint32_t y = 0; y < map.height; ++y) {
      for (uint32_t x = 0; x < map.width; ++x) {
        const auto [tanX, tanY] = tangents(map, fov, x, y, 1344, 1408, 32);
        texels.emplace_back(eccentricity_degrees(tanX, tanY), at(map, x, y));
      }
    }
    std::sort(texels.begin(), texels.end());
    for (size_t i = 1; i < texels.size(); ++i) {
      EXPECT_LE(texels[i].second, texels[i - 1].second);
    }
    // Every level shades the centre fully and saves something at the edges.
    EXPECT_EQ(texels.front().second, kFullDensity);
    EXPECT_LT(texels.back().second, kFullDensity);
  }
}

TEST(Foveation, EachEyeCentresOnItsOwnForwardDirection) {
  // The asymmetric frustum puts the forward direction off the image centre, towards the nose.
  const auto fullColumns = [](const Map& map) {
    double sum = 0.0;
    uint32_t count = 0;
    for (uint32_t y = 0; y < map.height; ++y) {
      for (uint32_t x = 0; x < map.width; ++x) {
        if (at(map, x, y) == kFullDensity) {
          sum += x + 0.5;
          ++count;
        }
      }
    }
    return count > 0 ? sum / count : 0.0;
  };
  const Map left = build_map(Level::High, left_eye());
  const Map right = build_map(Level::High, right_eye());
  const EyeFov fov = left_eye();
  const double forward = -fov.tanLeft / (fov.tanRight - fov.tanLeft) * left.width;
  EXPECT_NEAR(fullColumns(left), forward, 1.0);
  EXPECT_GT(fullColumns(left), left.width / 2.0);
  EXPECT_NEAR(fullColumns(right), right.width - fullColumns(left), 1.0);
}

TEST(Foveation, HigherLevelsNeverShadeMore) {
  const Map low = build_map(Level::Low);
  const Map medium = build_map(Level::Medium);
  const Map high = build_map(Level::High);
  for (size_t i = 0; i < low.rg8.size(); ++i) {
    EXPECT_LE(medium.rg8[i], low.rg8[i]);
    EXPECT_LE(high.rg8[i], medium.rg8[i]);
  }
  // Low never goes below half.
  EXPECT_TRUE(std::none_of(low.rg8.begin(), low.rg8.end(), [](uint8_t value) { return value == kQuarterDensity; }));
}

TEST(Foveation, LowAndMediumKeepTheHudScreenAtHalfDensity) {
  // The default HUD screen: 2.4 m wide at 2 m, with a 4:3 picture, looking straight ahead.
  constexpr float kHalfWidth = 1.2f / 2.0f;
  constexpr float kHalfHeight = 0.9f / 2.0f;
  const EyeFov fov = left_eye();
  for (Level level : {Level::Low, Level::Medium}) {
    const Map map = build_map(level, fov);
    uint32_t covered = 0;
    for (uint32_t y = 0; y < map.height; ++y) {
      for (uint32_t x = 0; x < map.width; ++x) {
        const auto [tanX, tanY] = tangents(map, fov, x, y, 1344, 1408, 32);
        if (std::abs(tanX) <= kHalfWidth && std::abs(tanY) <= kHalfHeight) {
          EXPECT_GE(at(map, x, y), kHalfDensity) << "level " << int(level) << " at " << x << "," << y;
          ++covered;
        }
      }
    }
    EXPECT_GT(covered, 100u);
  }
}

TEST(Foveation, ReadsTheFieldOfViewBackFromTheEyeProjection) {
  const EyeFov fov = left_eye();
  std::array<float, 16> projection{};
  // openxr_integration.cpp's ProjectionFromFov.
  projection[0] = 2.0f / (fov.tanRight - fov.tanLeft);
  projection[2] = (fov.tanRight + fov.tanLeft) / (fov.tanRight - fov.tanLeft);
  projection[5] = 2.0f / (fov.tanUp - fov.tanDown);
  projection[6] = (fov.tanUp + fov.tanDown) / (fov.tanUp - fov.tanDown);
  const EyeFov read = fov_from_projection(projection.data());
  EXPECT_NEAR(read.tanLeft, fov.tanLeft, 1e-5f);
  EXPECT_NEAR(read.tanRight, fov.tanRight, 1e-5f);
  EXPECT_NEAR(read.tanDown, fov.tanDown, 1e-5f);
  EXPECT_NEAR(read.tanUp, fov.tanUp, 1e-5f);

  // A projection without a frustum scale leaves the symmetric default.
  const std::array<float, 16> empty{};
  const EyeFov fallback = fov_from_projection(empty.data());
  EXPECT_EQ(fallback.tanLeft, -1.0f);
  EXPECT_EQ(fallback.tanUp, 1.0f);
}

// Eye-tracked foveation: the full-density centre follows the gaze.

// The pixel a gaze lands on, as build lays the eye out.
std::pair<float, float> gaze_pixel(const EyeFov& fov, const Gaze& gaze, uint32_t width, uint32_t height) {
  return {(gaze.tanX - fov.tanLeft) / (fov.tanRight - fov.tanLeft) * width,
          (gaze.tanY - fov.tanUp) / (fov.tanDown - fov.tanUp) * height};
}

TEST(Foveation, TheForwardGazeKeepsTheFixedMap) {
  for (Level level : {Level::Low, Level::Medium, Level::High}) {
    Map gazed;
    foveation::build(1344, 1408, 32, left_eye(), level, gazed, Gaze{});
    EXPECT_TRUE(gazed.rg8 == build_map(level).rg8) << "level " << int(level);
  }
  // The general angle agrees with the forward one.
  for (float tanX : {-1.2f, -0.3f, 0.0f, 0.4f, 0.9f}) {
    for (float tanY : {-1.0f, 0.0f, 0.7f}) {
      EXPECT_NEAR(angle_from_gaze_degrees(tanX, tanY, Gaze{}), eccentricity_degrees(tanX, tanY), 0.01f);
    }
  }
}

TEST(Foveation, TheFullDensityRegionFollowsTheGaze) {
  const EyeFov fov = left_eye();
  // Down and to the right, off the forward direction, with the widened full-density region still
  // inside the eye so its centre is not pulled in by the edge.
  const Gaze gaze{.tanX = std::tan(12.0f * kDegrees), .tanY = std::tan(-10.0f * kDegrees)};
  Map map;
  foveation::build(1344, 1408, 32, fov, Level::High, map, gaze);
  double sumX = 0.0;
  double sumY = 0.0;
  uint32_t count = 0;
  for (uint32_t y = 0; y < map.height; ++y) {
    for (uint32_t x = 0; x < map.width; ++x) {
      if (at(map, x, y) == kFullDensity) {
        sumX += x + 0.5;
        sumY += y + 0.5;
        ++count;
      }
    }
  }
  ASSERT_GT(count, 0u);
  const auto [pixelX, pixelY] = gaze_pixel(fov, gaze, 1344, 1408);
  EXPECT_NEAR(sumX / count, pixelX / 32.0, 1.5);
  EXPECT_NEAR(sumY / count, pixelY / 32.0, 1.5);
  // Where the forward map was sharpest, the far side of the gaze is now coarse.
  const Map fixed = build_map(Level::High, fov);
  EXPECT_EQ(at(map, static_cast<uint32_t>(pixelX / 32.0f), static_cast<uint32_t>(pixelY / 32.0f)), kFullDensity);
  EXPECT_EQ(at(fixed, 0, 0), kQuarterDensity);
  EXPECT_EQ(at(map, 0, 0), kQuarterDensity);
}

TEST(Foveation, DensityNeverRisesAwayFromTheGaze) {
  const EyeFov fov = left_eye();
  const Gaze gaze{.tanX = -0.35f, .tanY = 0.2f};
  for (Level level : {Level::Low, Level::Medium, Level::High}) {
    Map map;
    foveation::build(1344, 1408, 32, fov, level, map, gaze);
    std::vector<std::pair<float, uint8_t>> texels;
    for (uint32_t y = 0; y < map.height; ++y) {
      for (uint32_t x = 0; x < map.width; ++x) {
        const auto [tanX, tanY] = tangents(map, fov, x, y, 1344, 1408, 32);
        texels.emplace_back(angle_from_gaze_degrees(tanX, tanY, gaze), at(map, x, y));
      }
    }
    std::sort(texels.begin(), texels.end());
    for (size_t i = 1; i < texels.size(); ++i) {
      EXPECT_LE(texels[i].second, texels[i - 1].second);
    }
    EXPECT_EQ(texels.front().second, kFullDensity);
  }
}

TEST(Foveation, GazeCellsSnapTheGazeAndStayInsideTheEye) {
  const EyeFov fov = left_eye();
  constexpr uint32_t kWidth = 1344, kHeight = 1408, kTexel = 32;
  constexpr float kCellPixels = kTexel * kGazeCellTexels;
  // A cell's own gaze lies within half a cell of every gaze that falls in it.
  for (float tanX : {-0.9f, -0.2f, 0.0f, 0.31f, 0.8f}) {
    for (float tanY : {-0.8f, 0.0f, 0.45f}) {
      const Gaze gaze{.tanX = tanX, .tanY = tanY};
      const GazeCell cell = gaze_cell(kWidth, kHeight, kTexel, fov, gaze);
      const Gaze centre = cell_gaze(kWidth, kHeight, kTexel, fov, cell);
      const auto [gx, gy] = gaze_pixel(fov, gaze, kWidth, kHeight);
      const auto [cx, cy] = gaze_pixel(fov, centre, kWidth, kHeight);
      EXPECT_LE(std::abs(gx - cx), kCellPixels / 2.0f + 0.01f);
      EXPECT_LE(std::abs(gy - cy), kCellPixels / 2.0f + 0.01f);
      EXPECT_TRUE(gaze_cell(kWidth, kHeight, kTexel, fov, centre) == cell);
    }
  }
  // Gazes a few pixels apart share a cell; the forward direction has one of its own.
  const Gaze forward{};
  const GazeCell forwardCell = gaze_cell(kWidth, kHeight, kTexel, fov, forward);
  const auto [fx, fy] = gaze_pixel(fov, forward, kWidth, kHeight);
  EXPECT_EQ(forwardCell.x, static_cast<int32_t>(fx / kCellPixels));
  EXPECT_EQ(forwardCell.y, static_cast<int32_t>(fy / kCellPixels));
  // Beyond the eye, and not a number at all.
  const int32_t lastColumn = static_cast<int32_t>(std::ceil(kWidth / kCellPixels)) - 1;
  const int32_t lastRow = static_cast<int32_t>(std::ceil(kHeight / kCellPixels)) - 1;
  const GazeCell far = gaze_cell(kWidth, kHeight, kTexel, fov, Gaze{.tanX = 10.0f, .tanY = -10.0f});
  EXPECT_EQ(far.x, lastColumn);
  EXPECT_EQ(far.y, lastRow);
  const GazeCell farOther = gaze_cell(kWidth, kHeight, kTexel, fov, Gaze{.tanX = -10.0f, .tanY = 10.0f});
  EXPECT_EQ(farOther.x, 0);
  EXPECT_EQ(farOther.y, 0);
  EXPECT_TRUE(gaze_cell(kWidth, kHeight, kTexel, fov, Gaze{.tanX = NAN, .tanY = 0.2f}) == forwardCell);
}

} // namespace
} // namespace aurora::gfx::foveation
