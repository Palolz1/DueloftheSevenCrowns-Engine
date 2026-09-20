// duel_engine.h
// Godot 4.x GDExtension - C++ Engine for Duel of the Seven Crowns
// v2.1: Lazy SMP, 4-way bucketed TT w/ prefetch, MVV-LVA, butterfly history w/ gravity,
//       IID, passed donkey / outpost / king-structure eval
//
// Bug fixes vs v2.0:
//  - TTEntry::value changed int16_t -> int32_t (int16_t overflows for mate scores ±1,000,000)
//  - Struct reordered to maintain 16-byte size without alignment padding waste
//  - smp_worker: helpers do true independent iterative deepening with depth skipping
//    and per-thread root-move rotation (genuine Lazy SMP diversification)
//
// Bug fixes vs v2.1:
//  - TTEntry rebuilt as lockless (XOR-checksum) hashing. DEFAULT_SMP_THREADS threads
//    were reading/writing the same TTEntry via plain non-atomic field writes with zero
//    synchronization; a torn write from one thread interleaved with another produced
//    corrupted entries that probe() trusted outright. Observed in practice as TT-stored
//    scores exceeding ±MATE_SCORE (impossible from correct search output) and the engine
//    permanently latching onto a depth-1 phantom "mate" for the rest of a game.

#ifndef DUEL_ENGINE_H
#define DUEL_ENGINE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstdint>
#include <array>
#include <vector>
#include <algorithm>
#include <chrono>
#include <random>
#include <string>
#include <memory>
#include <cstring>
#include <atomic>
#include <thread>
#include <mutex>

using namespace godot;

// ── Constants ───────────────────────────────────────────────────
constexpr int BOARD_SIZE = 7;
constexpr int TOTAL_SQUARES = 49;
constexpr int MATE_SCORE = 1'000'000;
constexpr int NEAR_MATE = MATE_SCORE - 20'000;
constexpr int MAX_PLY = 64;
constexpr int MAX_EXTENSIONS = 16;
constexpr int MATE_BOUND = MATE_SCORE - MAX_PLY; // scores >= this are mate-ish

// Number of search threads (1 main + N-1 helpers). Tune to core count.
// DEFAULT_SMP_THREADS is now a CEILING, not a fixed count: the actual thread
// count used at runtime is computed from std::thread::hardware_concurrency()
// (see recommended_thread_count() below) and clamped to this maximum. This
// also bounds smp_worker's SKIP_MODS[] indexing, so it must stay >= 1 and
// match (or exceed) the array's intended size.
constexpr int DEFAULT_SMP_THREADS = 15;

// Returns a sensible search-thread count for the current machine:
// hardware_concurrency() - 1 (reserve one core for the OS/Godot main thread),
// clamped to [1, DEFAULT_SMP_THREADS]. hardware_concurrency() can legally
// return 0 if the platform can't determine core count, so that's treated as
// "unknown" and falls back to 1 (single-threaded, safest default).
inline int recommended_thread_count()
{
    unsigned hw = std::thread::hardware_concurrency();
    if (hw == 0)
        return 1;
    int usable = static_cast<int>(hw) - 1;
    if (usable < 1)
        usable = 1;
    if (usable > DEFAULT_SMP_THREADS)
        usable = DEFAULT_SMP_THREADS;
    return usable;
}

// ── Zobrist keys ────────────────────────────────────────────────
struct ZobristKeys
{
    uint64_t piece_square[19][7][7]; // index = piece_code + 9 (-9..9 -> 0..18)
    uint64_t turn;

    // The 40-move no-progress rule means the SAME physical position can have
    // a completely different game-theoretic value depending on how close the
    // halfmove clock is to triggering it (Evaluator::evaluate and negamax
    // both hard-branch on hm >= 40). FastBoard's zhash only encodes piece
    // placement + turn, so without this, a TT entry computed early in a long
    // no-capture sequence (clock not yet a concern) gets silently reused much
    // later in the SAME sequence (clock about to expire) -- the engine ends
    // up trusting a stale "I'm winning" verdict instead of recalculating with
    // real urgency. Only bucketed for hm >= 20 (comfortably inside the zone
    // where the clock can plausibly matter within a deep search) so normal
    // transpositions elsewhere in the game are unaffected.
    uint64_t halfmove_zone[21]; // covers hm 20..40

    ZobristKeys();

    inline uint64_t hm_key(int hm) const
    {
        if (hm < 20)
            return 0;
        return halfmove_zone[std::min(hm, 40) - 20];
    }
};

// ── Transposition Table ─────────────────────────────────────────
//
// 4-way set-associative bucket TT.  Each bucket is exactly one 64-byte
// cache line holding 4 entries of 16 bytes each.
//
// v2.2 FIX: TTEntry is now two atomic<uint64_t> words (lock/data) using
// lockless hashing (the classic Kerrigan/Hyatt XOR trick, as used by
// Stockfish's TT). With DEFAULT_SMP_THREADS concurrent threads reading
// and writing the SAME bucket with zero locking, a torn write (thread A's
// partial write interleaved with thread B's) used to be silently trusted
// as a valid entry -- producing corrupted scores (observed in practice:
// stored values exceeding +/-MATE_SCORE, which is mathematically
// impossible from correct search output). Now: the payload is packed into
// a single 64-bit word ("data"), and lock = full_key ^ data. On probe, a
// torn combination of (lock, data) will essentially never reproduce a
// real position's key when XORed together, so it's safely rejected as a
// miss instead of corrupting the search.
//
// Layout (16 bytes):
//   lock  atomic<uint64_t>  full Zobrist key XOR data -- torn-write guard
//   data  atomic<uint64_t>  packed {value:24, best_move:18, depth:7, flag:2, age:8}
//
// Packed data bit layout (LSB -> MSB):
//   [0..23]  value      bias-encoded signed (bias = 1<<23), covers +/-8.3M
//   [24..41] best_move  matches MoveGenerator::pack_move's 18-bit encoding
//   [42..48] depth      0..127
//   [49..50] flag       TT_EXACT / TT_LOWER / TT_UPPER / TT_NONE
//   [51..58] age        TT generation counter, 0..255
//   [59..63] unused

enum TTFlag : uint8_t
{
    TT_EXACT = 0,
    TT_LOWER = 1,
    TT_UPPER = 2,
    TT_NONE = 3
};

struct alignas(16) TTEntry
{
    std::atomic<uint64_t> lock; // full Zobrist key XOR data
    std::atomic<uint64_t> data; // packed {value, best_move, depth, flag, age}

    TTEntry() : lock(0), data(0) {}
};
static_assert(sizeof(TTEntry) == 16, "TTEntry must be exactly 16 bytes");
static_assert(std::atomic<uint64_t>::is_always_lock_free,
              "Target must support lock-free 64-bit atomics for the lockless TT");

// 4 entries per bucket = 64-byte cache line
struct alignas(64) TTBucket
{
    TTEntry e[4];
};
static_assert(sizeof(TTBucket) == 64, "TTBucket must be exactly 64 bytes");

// 1<<20 buckets x 64 bytes = 64 MB shared table
constexpr size_t TT_BUCKETS = 1 << 20;

struct SharedTT
{
    TTBucket buckets[TT_BUCKETS];

    void clear();

    // Returns true (cutoff/exact) if the entry is deep enough for the current
    // search.  Always writes out_move if a signature match is found, even when
    // depth is insufficient (used for IID move ordering).
    bool probe(uint64_t key, int depth, int alpha, int beta, int ply,
               uint32_t &out_move, int &out_score, TTFlag &out_flag) const;

    void store(uint64_t key, int depth, TTFlag flag, int value,
               uint32_t best_move, uint8_t age, int ply);

    inline void prefetch(uint64_t key) const
    {
        const void *p = &buckets[key & (TT_BUCKETS - 1)];
#if defined(__GNUC__) || defined(__clang__)
        __builtin_prefetch(p, 0, 1);
#elif defined(_MSC_VER)
        _mm_prefetch(reinterpret_cast<const char *>(p), _MM_HINT_T1);
#endif
    }
};

// ── FastBoard ───────────────────────────────────────────────────
class FastBoard
{
public:
    std::array<int8_t, TOTAL_SQUARES> grid;
    int8_t turn;
    uint64_t zhash;
    int wking_sq;
    int bking_sq;

    struct HistoryEntry
    {
        uint8_t from_sq, to_sq;
        int8_t piece, captured;
        uint64_t old_hash;
    };
    std::vector<HistoryEntry> history;

    FastBoard();
    FastBoard(const FastBoard &other);

    static inline int sq(int r, int c) { return r * BOARD_SIZE + c; }
    static inline int row(int s) { return s / BOARD_SIZE; }
    static inline int col(int s) { return s % BOARD_SIZE; }

    void make_move(uint32_t move, const ZobristKeys &zobrist);
    void unmake_move();
    bool is_in_check(int8_t color) const;
    bool is_insufficient_material() const;
};

// ── Move Generator ──────────────────────────────────────────────
class MoveGenerator
{
public:
    static std::vector<uint32_t> generate_pseudo_moves(const FastBoard &fb);
    static std::vector<uint32_t> generate_legal_moves(const FastBoard &fb);
    static std::vector<uint32_t> generate_captures(const FastBoard &fb);
    static std::vector<uint32_t> generate_piece_pseudo_moves(const FastBoard &fb, int r, int c);
    static std::vector<uint32_t> generate_piece_attack_squares(const FastBoard &fb, int r, int c);

    static uint32_t pack_move(int fr, int fc, int tr, int tc, int captured);
    static void unpack_move(uint32_t move, int &fr, int &fc, int &tr, int &tc, int &captured);
    static bool piece_attacks(const FastBoard &fb, int fr, int fc, int tr, int tc, int piece_code);
    static void add_piece_moves(const FastBoard &fb, int r, int c, int p,
                                std::vector<uint32_t> &moves);

private:
    static void try_add(const FastBoard &fb, int r, int c, int nr, int nc, int p,
                        std::vector<uint32_t> &moves);
    static void slide(const FastBoard &fb, int r, int c, int dr, int dc, int p,
                      std::vector<uint32_t> &moves);
};

// ── Evaluator ──────────────────────────────────────────────────
class Evaluator
{
public:
    static int evaluate(const FastBoard &fb, int halfmove_clock);
    static int see(const FastBoard &fb, uint32_t move);

    // Indexed by |piece_code|: 0=empty, 2=King, 3=Knight, 4=Cardinal,
    // 5=Paladin, 6=Marshall, 7=Donkey, 8=Lancer, 9=Warden
    static constexpr int PIECE_VALUES[10] = {0, 0, 50000, 305, 475, 475, 850, 100, 550, 450};

private:
    static constexpr int PHASE_WEIGHTS[10] = {0, 0, 0, 1, 2, 2, 3, 0, 2, 2};
    static constexpr int TOTAL_MAX_PHASE = 20;

    static const int PST_MG_W[7][7], PST_MG_B[7][7];
    static const int PST_EG_W[7][7], PST_EG_B[7][7];
    static const int KING_MG_W[7][7], KING_MG_B[7][7];
    static const int KING_EG_W[7][7], KING_EG_B[7][7];

    static constexpr int MOBILITY_WEIGHT_MG = 5;
    static constexpr int MOBILITY_WEIGHT_EG = 3;
    static constexpr int MOBILITY_MULT_MG[10] = {0, 0, 0, 3, 2, 2, 2, 1, 2, 2};
    static constexpr int MOBILITY_MULT_EG[10] = {0, 0, 0, 2, 1, 1, 2, 2, 2, 1};
    static constexpr int TRAPPED_PENALTY_MG = 180;
    static constexpr int TRAPPED_PENALTY_EG = 80;
    static constexpr int CRAMPED_PENALTY_MG = 65;
    static constexpr int CRAMPED_PENALTY_EG = 25;
    static constexpr int DONKEY_ADV_MG = 10;
    static constexpr int DONKEY_ADV_EG = 25;
    static constexpr int PASSED_DONKEY_MG = 30;
    static constexpr int PASSED_DONKEY_EG = 70;
    static constexpr int OUTPOST_MG = 25;
    static constexpr int OUTPOST_EG = 10;
    static constexpr int KING_OPEN_FILE_PEN_MG = 40;
    static constexpr int KING_OPEN_FILE_PEN_EG = 20;
    static constexpr int KING_SHIELD_BONUS_MG = 15;
    static constexpr int KING_SHIELD_BONUS_EG = 5;
    static constexpr int ESCAPE_PENALTY_MG[9] = {500, 240, 90, 0, 0, 0, 0, 0, 0};
    static constexpr int ESCAPE_PENALTY_EG[9] = {200, 80, 20, 0, 0, 0, 0, 0, 0};
    static constexpr float KING_DANGER_SCALE_MG = 1.0f;
    static constexpr float KING_DANGER_SCALE_EG = 0.25f;
    static constexpr int TROPISM_WEIGHTS[10] = {0, 0, 0, 6, 8, 8, 9, 2, 7, 7};
    static constexpr int TEMPO_BONUS = 25;

    static inline int lerp(int mg, int eg, float phase)
    {
        return static_cast<int>(mg * phase + eg * (1.0f - phase));
    }

    static float compute_phase(const FastBoard &fb);
    static int count_pseudo_mobility(const FastBoard &fb, int r, int c, int p);
    static int king_escape_score(const FastBoard &fb, int kr, int kc, int color);
    static int king_danger(const FastBoard &fb, int king_r, int king_c, int attacker_sign);
    static bool is_passed_donkey(const FastBoard &fb, int r, int c, int p);
    static bool is_outpost(const FastBoard &fb, int r, int c, int color);
    static int king_structure(const FastBoard &fb, int kr, int kc, int color, float phase);
};

// ── Per-thread search state ─────────────────────────────────────
// One instance per search thread.  Never shared — no synchronisation needed.
struct ThreadData
{
    int id{0};
    int nodes{0};
    int gravity_counter{0};

    // Search heuristic tables
    std::array<std::array<uint32_t, 2>, MAX_PLY> killers{};
    int history[7][7][7][7]{};
    uint32_t countermoves[10][49]{};
    int16_t cont_history[10][49][49][49]{};
    int static_eval_stack[MAX_PLY + 4]{};

    // History gravity: right-shift all history values every GRAVITY_INTERVAL
    // nodes to prevent saturation and age out stale information.
    static constexpr int GRAVITY_INTERVAL = 1024;
    static constexpr int NO_EVAL = 1'000'000;

    void clear();
    void maybe_apply_gravity();
};

// ── Searcher ────────────────────────────────────────────────────
class Searcher
{
public:
    ZobristKeys zobrist;
    SharedTT shared_tt; // heap-allocated via unique_ptr<Searcher>

    struct SearchResult
    {
        uint32_t best_move{0};
        int score{0};
        String mate_info;
        int depth_reached{0};
        int nodes_searched{0};
        double time_ms{0.0};
    };

    Searcher();

    SearchResult find_best_move(const FastBoard &fb, int max_depth,
                                double time_limit_sec, int halfmove_clock,
                                int num_threads = DEFAULT_SMP_THREADS);

    int evaluate_board(const FastBoard &fb, int halfmove_clock);
    void clear_tables();

private:
    static constexpr int NO_EVAL = 1'000'000;

    int tt_age{0};

    // Shared across all threads — atomic for correctness, relaxed for speed
    std::atomic<bool> timed_out{false};
    std::atomic<uint32_t> atomic_best_move{0};
    std::atomic<int> atomic_best_score{0};
    std::atomic<int> atomic_total_nodes{0};

    std::chrono::steady_clock::time_point deadline;

    // SMP worker: genuine independent iterative deepening with
    // per-thread personality (depth skipping + root-move rotation).
    // board is passed by value so each thread owns its own copy
    // (the caller moves or copies before handing off).
    void smp_worker(FastBoard board, // intentional by-value: thread owns it
                    int thread_id,
                    int max_depth,
                    int halfmove_clock,
                    int wp, int bp,
                    std::vector<uint32_t> root_moves); // pre-rotated root order

    int quiescence(FastBoard &fb, int alpha, int beta, int ply, int hm,
                   ThreadData &td);

    int negamax(FastBoard &fb, int depth, int alpha, int beta, int ply,
                bool allow_null, int wp, int bp, int extensions, int hm,
                ThreadData &td);

    std::vector<uint32_t> order_moves(FastBoard &fb,
                                      const std::vector<uint32_t> &moves,
                                      int ply, uint32_t tt_move,
                                      uint32_t countermove,
                                      ThreadData &td);

    // MVV-LVA: higher victim × lower attacker = better score (no board scan)
    static inline int mvv_lva(int victim_pt, int attacker_pt)
    {
        return Evaluator::PIECE_VALUES[victim_pt] * 16 - Evaluator::PIECE_VALUES[attacker_pt];
    }

    static String format_mate(int white_score);
};

// ── Godot Wrapper ───────────────────────────────────────────────
class DuelEngine : public RefCounted
{
    GDCLASS(DuelEngine, RefCounted)

private:
    std::unique_ptr<Searcher> searcher; // heap-allocates SharedTT (64 MB)

protected:
    static void _bind_methods();

public:
    DuelEngine();
    ~DuelEngine() = default;

    void set_board(const Array &board_array, const String &turn);
    Dictionary find_best_move(int max_depth, double time_limit, int halfmove_clock, int num_threads = -1);
    int get_recommended_threads();
    float evaluate_position(int halfmove_clock);
    Array get_legal_moves(int row, int col);
    Array get_piece_moves(int row, int col);
    Array get_piece_attack_squares(int row, int col);
    bool is_checkmate();
    bool is_in_check(const String &color);
    bool is_insufficient_material();
    bool make_move(int from_r, int from_c, int to_r, int to_c);
    void undo_move();
    void clear_tables();
    String get_engine_info();
    int64_t perft(int depth);
    Dictionary perft_divide(int depth);

    FastBoard board;
};

#endif // DUEL_ENGINE_H