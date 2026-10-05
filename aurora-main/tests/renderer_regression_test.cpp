#include "gx_test_common.hpp"
#include "gfx/staging_map.hpp"
#include "gx/pipeline.hpp"

#include <thread>

using aurora::gx::g_gxState;

namespace {
std::vector<u8> draw(GXPrimitive primitive, u16 count, GXVtxFmt format = GX_VTXFMT0) {
  std::vector<u8> bytes{static_cast<u8>(primitive | format), static_cast<u8>(count >> 8), static_cast<u8>(count)};
  bytes.resize(3 + count);
  return bytes;
}
} // namespace

TEST_F(GXFifoTest, MaximumQuadCountTerminatesWithoutOutOfRangeIndices) {
  g_gxState.lastVtxFmt = GX_VTXFMT0;
  g_gxState.lastVtxSize = 1;
  for (const u16 count : {65532, 65533, 65534, 65535}) {
    g_gxState.stateDirty = true;
    decode_fifo(draw(GX_QUADS, count));
    const auto& indices = aurora::gfx::testing::last_pushed_indices();
    ASSERT_EQ(indices.size(), (count / 4) * 6 + (count % 4 == 3 ? 3 : 0));
    for (const auto index : indices)
      ASSERT_LT(index, count);
  }
}

TEST_F(GXFifoTest, IncompletePrimitivesNeverJoinAcrossDraws) {
  g_gxState.lastVtxFmt = GX_VTXFMT0;
  g_gxState.lastVtxSize = 1;
  aurora::gfx::testing::use_draw_command_tracking(true);
  decode_fifo(draw(GX_TRIANGLES, 4));
  EXPECT_EQ(aurora::gfx::testing::last_pushed_indices(), (std::vector<u16>{0, 1, 2}));
  decode_fifo(draw(GX_TRIANGLES, 5));
  EXPECT_EQ(aurora::gfx::testing::last_pushed_indices(), (std::vector<u16>{4, 5, 6}));
  const auto before = aurora::gfx::testing::last_pushed_indices();
  decode_fifo(draw(GX_TRIANGLEFAN, 2));
  EXPECT_EQ(aurora::gfx::testing::last_pushed_indices(), before);
}

TEST_F(GXFifoTest, MergeStopsBeforeSixteenBitIndexOverflow) {
  g_gxState.lastVtxFmt = GX_VTXFMT0;
  g_gxState.lastVtxSize = 1;
  aurora::gfx::testing::use_draw_command_tracking(true);
  decode_fifo(draw(GX_TRIANGLES, 65535));
  decode_fifo(draw(GX_TRIANGLES, 3));
  EXPECT_EQ(aurora::gfx::g_mergedDrawCallCount, 0u);
  EXPECT_EQ(aurora::gfx::testing::last_pushed_indices(), (std::vector<u16>{0, 1, 2}));
}

TEST_F(GXFifoTest, VertexCacheInvalidationBreaksDrawMerging) {
  g_gxState.lastVtxFmt = GX_VTXFMT0;
  g_gxState.lastVtxSize = 1;
  aurora::gfx::testing::use_draw_command_tracking(true);
  decode_fifo(draw(GX_TRIANGLES, 3));
  decode_fifo({GX_CMD_INVL_VC});
  EXPECT_TRUE(g_gxState.stateDirty);
  decode_fifo(draw(GX_TRIANGLES, 3));
  EXPECT_EQ(aurora::gfx::g_mergedDrawCallCount, 0u);
}

TEST_F(GXFifoTest, EqualStrideVertexFormatChangeBreaksDrawMerging) {
  aurora::gfx::testing::use_real_vertex_format_helpers(true);
  g_gxState.vtxDesc[GX_VA_POS] = GX_DIRECT;
  for (const auto format : {GX_VTXFMT0, GX_VTXFMT1}) {
    g_gxState.vtxFmts[format].attrs[GX_VA_POS].cnt = GX_POS_XY;
    g_gxState.vtxFmts[format].attrs[GX_VA_POS].type = GX_U8;
  }
  g_gxState.vtxFmts[GX_VTXFMT1].attrs[GX_VA_POS].frac = 1;
  aurora::gfx::testing::use_draw_command_tracking(true);
  for (const auto format : {GX_VTXFMT0, GX_VTXFMT1}) {
    auto bytes = draw(GX_TRIANGLES, 3, format);
    bytes.resize(9);
    decode_fifo(bytes);
  }
  EXPECT_EQ(aurora::gfx::g_mergedDrawCallCount, 0u);
}

TEST_F(GXFifoTest, SingleExpandedPrimitiveCannotMergeWithTriangles) {
  g_gxState.lastVtxFmt = GX_VTXFMT0;
  g_gxState.lastVtxSize = 1;
  aurora::gfx::testing::use_draw_command_tracking(true);
  decode_fifo(draw(GX_POINTS, 1));
  decode_fifo(draw(GX_TRIANGLES, 3));
  EXPECT_EQ(aurora::gfx::g_mergedDrawCallCount, 0u);
  EXPECT_EQ(aurora::gfx::testing::last_pushed_indices(), (std::vector<u16>{0, 1, 2}));
}

TEST(StagingMapping, RetiredCallbacksCannotPublishAnotherBuffersReadiness) {
  using namespace aurora::gfx;
  StagingMapState state;
  const auto old = state.request();
  EXPECT_EQ(state.request(), 0u);
  state.reset();
  const auto current = state.request();
  EXPECT_FALSE(state.complete(old, BufferMapState::Mapped));
  EXPECT_FALSE(state.complete(old, BufferMapState::Unmapped));
  EXPECT_EQ(state.state(), BufferMapState::Mapping);
  EXPECT_TRUE(state.complete(current, BufferMapState::Mapped));
  EXPECT_FALSE(state.complete(current, BufferMapState::Unmapped));
  EXPECT_EQ(state.state(), BufferMapState::Mapped);
}

TEST(StagingMapping, AsyncCompletionWakesWaiters) {
  using namespace aurora::gfx;
  StagingMapState state;
  const auto generation = state.request();
  std::thread callback([&] {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    state.complete(generation, BufferMapState::Mapped);
  });
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (state.state() == BufferMapState::Mapping && std::chrono::steady_clock::now() < deadline)
    state.wait_for_progress();
  callback.join();
  EXPECT_EQ(state.state(), BufferMapState::Mapped);
}
