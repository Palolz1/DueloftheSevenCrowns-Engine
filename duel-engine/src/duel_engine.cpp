// duel_engine.cpp
// Duel of the Seven Crowns — v2.2
//
// Fixes vs v2.0:
//   1. TTEntry::value is now int32_t (was int16_t — overflowed for mate scores).
//   2. smp_worker takes FastBoard by value explicitly (caller moves in a copy;
//      no ambiguous reference-to-local threading hazard).
//   3. Lazy SMP helpers run genuine independent iterative deepening with:
//        - Depth skipping: thread i skips depth d if (d + thread_id) % skip_mod != 0
//          so threads spread across the depth tree rather than stampeding the same node.
//        - Root-move rotation: each helper starts its root list at offset (thread_id)
//          so they fan out across different first moves and populate the TT broadly.
//        - Independent aspiration windows seeded from the shared best score.
//
// Fixes vs v2.1:
//   4. SharedTT rebuilt as lockless (XOR-checksum) hashing. The old TTEntry had five
//      separate non-atomic fields, written/read by up to DEFAULT_SMP_THREADS threads
//      concurrently with zero synchronization. A torn write (one thread's write
//      interleaved with another's on the same bucket) produced a corrupted entry that
//      probe() trusted unconditionally — no check ever existed to catch it. Symptom
//      seen in self-play logs: TT-stored scores exceeding ±MATE_SCORE (mathematically
//      impossible from correct negamax output), and the engine permanently latching
//      onto a depth-1, single-node phantom "mate" for the rest of the game instead of
//      ever searching again (find_best_move's `if (abs(score) >= NEAR_MATE) break;`
//      trusts the very first near-mate score it sees). Each TTEntry is now exactly two
//      atomic<uint64_t> words; a torn (lock, data) pair fails the XOR check and is
//      safely treated as a miss instead of corrupting search results.

#include "duel_engine.h"
#include <climits>
#include <cmath>
#include <cstring>

// ═══════════════════════════════════════════════════════════════
// Zobrist Keys
// ═══════════════════════════════════════════════════════════════
ZobristKeys::ZobristKeys()
{
    std::mt19937_64 rng(0xDEADBEEFCAFEBABEULL);
    for (int pc = 0; pc < 19; ++pc)
        for (int r = 0; r < 7; ++r)
            for (int c = 0; c < 7; ++c)
                piece_square[pc][r][c] = rng();
    turn = rng();
    for (int i = 0; i < 21; ++i)
        halfmove_zone[i] = rng();
}

// ═══════════════════════════════════════════════════════════════
// SharedTT — lockless hashing (Kerrigan/Hyatt XOR trick)
//
// v2.2: DEFAULT_SMP_THREADS threads share this table with zero locking.
// The old layout (5 separate non-atomic fields per entry) let one thread's
// partial write interleave with another's, producing "Frankenstein"
// entries -- e.g. a fresh value paired with a stale flag/depth from a
// different write. probe() had no way to detect this and would trust the
// torn entry outright. In testing this manifested as TT-stored scores
// exceeding +/-MATE_SCORE (mathematically impossible from correct search
// output) and, downstream, the engine permanently trusting a depth-1
// phantom "mate" and refusing to search further for the rest of the game.
//
// Fix: each entry is exactly two atomic<uint64_t> words. `data` packs the
// real payload; `lock` is `full_key ^ data`. A reader recomputes
// `lock ^ data` and only accepts the entry if it reproduces the probed
// key. A torn read (data from one write, lock from another) reconstructs
// to effectively-random garbage and fails this check overwhelmingly
// often, so it's safely treated as a miss instead of corrupting the
// search. No locks, no mutexes -- still fully lock-free.
// ═══════════════════════════════════════════════════════════════
namespace
{
    constexpr int TT_VAL_BITS = 24;
    constexpr int TT_MOVE_BITS = 18;
    constexpr int TT_DEPTH_BITS = 7;
    constexpr int TT_FLAG_BITS = 2;
    constexpr int TT_AGE_BITS = 8;

    constexpr int TT_VAL_SHIFT = 0;
    constexpr int TT_MOVE_SHIFT = TT_VAL_SHIFT + TT_VAL_BITS;     // 24
    constexpr int TT_DEPTH_SHIFT = TT_MOVE_SHIFT + TT_MOVE_BITS;  // 42
    constexpr int TT_FLAG_SHIFT = TT_DEPTH_SHIFT + TT_DEPTH_BITS; // 49
    constexpr int TT_AGE_SHIFT = TT_FLAG_SHIFT + TT_FLAG_BITS;    // 51

    constexpr uint64_t TT_VAL_MASK = (1ull << TT_VAL_BITS) - 1;
    constexpr uint64_t TT_MOVE_MASK = (1ull << TT_MOVE_BITS) - 1;
    constexpr uint64_t TT_DEPTH_MASK = (1ull << TT_DEPTH_BITS) - 1;
    constexpr uint64_t TT_FLAG_MASK = (1ull << TT_FLAG_BITS) - 1;
    constexpr uint64_t TT_AGE_MASK = (1ull << TT_AGE_BITS) - 1;

    // Bias so the 24-bit field can hold a signed value. Covers +/-8.39M,
    // comfortably clear of MATE_SCORE (1,000,000) plus any ply offset.
    constexpr int64_t TT_VAL_BIAS = 1ll << (TT_VAL_BITS - 1);

    inline uint64_t pack_tt_data(int32_t value, uint32_t best_move, int depth,
                                 TTFlag flag, uint8_t age)
    {
        uint64_t v = static_cast<uint64_t>(static_cast<int64_t>(value) + TT_VAL_BIAS) & TT_VAL_MASK;
        uint64_t m = static_cast<uint64_t>(best_move) & TT_MOVE_MASK;
        uint64_t d = static_cast<uint64_t>(std::clamp(depth, 0, static_cast<int>(TT_DEPTH_MASK))) & TT_DEPTH_MASK;
        uint64_t f = static_cast<uint64_t>(flag) & TT_FLAG_MASK;
        uint64_t a = static_cast<uint64_t>(age) & TT_AGE_MASK;
        return (v << TT_VAL_SHIFT) | (m << TT_MOVE_SHIFT) | (d << TT_DEPTH_SHIFT) |
               (f << TT_FLAG_SHIFT) | (a << TT_AGE_SHIFT);
    }

    inline void unpack_tt_data(uint64_t data, int32_t &value, uint32_t &best_move,
                               int &depth, TTFlag &flag, uint8_t &age)
    {
        value = static_cast<int32_t>((data >> TT_VAL_SHIFT) & TT_VAL_MASK) - static_cast<int32_t>(TT_VAL_BIAS);
        best_move = static_cast<uint32_t>((data >> TT_MOVE_SHIFT) & TT_MOVE_MASK);
        depth = static_cast<int>((data >> TT_DEPTH_SHIFT) & TT_DEPTH_MASK);
        flag = static_cast<TTFlag>((data >> TT_FLAG_SHIFT) & TT_FLAG_MASK);
        age = static_cast<uint8_t>((data >> TT_AGE_SHIFT) & TT_AGE_MASK);
    }
}

void SharedTT::clear()
{
    std::memset(buckets, 0, sizeof(buckets));
}

bool SharedTT::probe(uint64_t key, int depth, int alpha, int beta, int ply,
                     uint32_t &out_move, int &out_score, TTFlag &out_flag) const
{
    const TTBucket &bkt = buckets[key & (TT_BUCKETS - 1)];

    for (int i = 0; i < 4; ++i)
    {
        const TTEntry &e = bkt.e[i];
        uint64_t data = e.data.load(std::memory_order_relaxed);
        uint64_t lock = e.lock.load(std::memory_order_relaxed);

        // Rejects empty slots AND torn/corrupted writes from concurrent
        // threads in one check: only a write that completed atomically
        // as a (lock, data) pair will reproduce `key` here.
        if ((lock ^ data) != key)
            continue;

        int32_t value;
        uint32_t bm;
        int d;
        TTFlag f;
        uint8_t age;
        unpack_tt_data(data, value, bm, d, f, age);

        // Always return the move for ordering even if depth is too shallow
        out_move = bm;
        out_flag = f;

        // Denormalise mate score
        int val = value;
        if (val >= MATE_BOUND)
            val -= ply;
        else if (val <= -MATE_BOUND)
            val += ply;

        // A score is only achievable from THIS node if it falls within the
        // fastest-possible-mate window for this ply (mirrors the alpha/beta
        // clamp at the top of negamax). Without this, a mate score cached
        // from one transposition context can be reused at a different ply
        // and land outside what's actually reachable from here -- and since
        // that value gets returned, propagated up, and re-stored, the error
        // compounds with every round trip instead of staying bounded.
        val = std::clamp(val, -MATE_SCORE + ply, MATE_SCORE - ply - 1);
        out_score = val;

        // Only return a cut/exact result if the entry is deep enough
        if (d >= depth)
        {
            if (out_flag == TT_EXACT)
                return true;
            if (out_flag == TT_LOWER && val >= beta)
                return true;
            if (out_flag == TT_UPPER && val <= alpha)
                return true;
        }
        return false; // shallow hit: move is useful, but no cutoff
    }

    out_move = 0;
    out_score = 0;
    out_flag = TT_NONE;
    return false;
}

void SharedTT::store(uint64_t key, int depth, TTFlag flag, int value,
                     uint32_t best_move, uint8_t age, int ply)
{
    TTBucket &bkt = buckets[key & (TT_BUCKETS - 1)];

    // Same mate-distance window enforced on the probe() side: a score isn't
    // achievable from this ply if it implies a faster mate than is possible
    // from here. Clamping on the way IN (as well as the way out in probe())
    // stops a bad value from ever entering the table in the first place,
    // instead of just containing it after the fact.
    value = std::clamp(value, -MATE_SCORE + ply, MATE_SCORE - ply - 1);

    // Normalise mate score for storage (distance-to-mate becomes distance-from-root)
    int32_t stored = static_cast<int32_t>(value);
    if (value >= MATE_BOUND)
        stored = static_cast<int32_t>(value + ply);
    else if (value <= -MATE_BOUND)
        stored = static_cast<int32_t>(value - ply);

    // Replacement policy (unchanged from v2.1):
    // 1. Exact key match → overwrite if deeper, same age, or EXACT flag.
    // 2. Empty slot       → fill immediately.
    // 3. Otherwise evict the "lowest quality" entry (stale age >> depth).
    int worst_idx = 0;
    int worst_score = INT_MAX;

    for (int i = 0; i < 4; ++i)
    {
        TTEntry &e = bkt.e[i];
        uint64_t cur_data = e.data.load(std::memory_order_relaxed);
        uint64_t cur_lock = e.lock.load(std::memory_order_relaxed);
        bool is_empty = (cur_data == 0 && cur_lock == 0);
        bool is_match = !is_empty && ((cur_lock ^ cur_data) == key);

        if (is_match) // key match — update conditionally
        {
            int32_t old_value;
            uint32_t old_bm;
            int old_depth;
            TTFlag old_flag;
            uint8_t old_age;
            unpack_tt_data(cur_data, old_value, old_bm, old_depth, old_flag, old_age);

            if (flag == TT_EXACT || depth >= old_depth || old_age != age)
            {
                uint32_t bm = best_move ? best_move : old_bm;
                uint64_t new_data = pack_tt_data(stored, bm, depth, flag, age);
                e.data.store(new_data, std::memory_order_relaxed);
                e.lock.store(key ^ new_data, std::memory_order_relaxed);
            }
            return;
        }

        if (is_empty)
        {
            uint64_t new_data = pack_tt_data(stored, best_move, depth, flag, age);
            e.data.store(new_data, std::memory_order_relaxed);
            e.lock.store(key ^ new_data, std::memory_order_relaxed);
            return;
        }

        // Occupied by a different position — quality heuristic for eviction
        int32_t v_;
        uint32_t bm_;
        int d_;
        TTFlag f_;
        uint8_t a_;
        unpack_tt_data(cur_data, v_, bm_, d_, f_, a_);
        int age_penalty = (a_ != age) ? 8 : 0;
        int q = d_ - age_penalty;
        if (q < worst_score)
        {
            worst_score = q;
            worst_idx = i;
        }
    }

    // Evict lowest-quality slot
    TTEntry &ev = bkt.e[worst_idx];
    uint64_t new_data = pack_tt_data(stored, best_move, depth, flag, age);
    ev.data.store(new_data, std::memory_order_relaxed);
    ev.lock.store(key ^ new_data, std::memory_order_relaxed);
}

// ═══════════════════════════════════════════════════════════════
// ThreadData
// ═══════════════════════════════════════════════════════════════
void ThreadData::clear()
{
    nodes = 0;
    gravity_counter = 0;
    for (auto &pair : killers)
    {
        pair[0] = pair[1] = 0;
    }
    std::memset(history, 0, sizeof(history));
    std::memset(countermoves, 0, sizeof(countermoves));
    std::memset(cont_history, 0, sizeof(cont_history));
    for (int i = 0; i < MAX_PLY + 4; ++i)
        static_eval_stack[i] = NO_EVAL;
}

void ThreadData::maybe_apply_gravity()
{
    if (++gravity_counter < GRAVITY_INTERVAL)
        return;
    gravity_counter = 0;
    // Right-shift all history by 1: preserves relative ordering, prevents
    // saturation, and naturally ages out patterns from earlier in the game.
    for (int a = 0; a < 7; ++a)
        for (int b = 0; b < 7; ++b)
            for (int c = 0; c < 7; ++c)
                for (int d = 0; d < 7; ++d)
                    history[a][b][c][d] >>= 1;

    for (int a = 0; a < 10; ++a)
        for (int b = 0; b < 49; ++b)
            for (int c = 0; c < 49; ++c)
                for (int d = 0; d < 49; ++d)
                    cont_history[a][b][c][d] >>= 1;
}

// ═══════════════════════════════════════════════════════════════
// FastBoard
// ═══════════════════════════════════════════════════════════════
FastBoard::FastBoard() : turn(1), zhash(0), wking_sq(-1), bking_sq(-1)
{
    grid.fill(0);
}

FastBoard::FastBoard(const FastBoard &o)
    : grid(o.grid), turn(o.turn), zhash(o.zhash),
      wking_sq(o.wking_sq), bking_sq(o.bking_sq), history(o.history) {}

void FastBoard::make_move(uint32_t move, const ZobristKeys &zobrist)
{
    int fr, fc, tr, tc, captured;
    MoveGenerator::unpack_move(move, fr, fc, tr, tc, captured);

    int from_sq = sq(fr, fc), to_sq = sq(tr, tc);
    int8_t piece = grid[from_sq];
    int8_t target = grid[to_sq];

    HistoryEntry he;
    he.from_sq = static_cast<uint8_t>(from_sq);
    he.to_sq = static_cast<uint8_t>(to_sq);
    he.piece = piece;
    he.captured = target;
    he.old_hash = zhash;
    history.push_back(he);

    zhash ^= zobrist.piece_square[piece + 9][fr][fc];
    if (target != 0)
        zhash ^= zobrist.piece_square[target + 9][tr][tc];

    grid[from_sq] = 0;

    // Donkey promotion: reaches back rank -> becomes Lancer
    if (std::abs(piece) == 7)
        if ((piece > 0 && tr == 6) || (piece < 0 && tr == 0))
            piece = (piece > 0) ? 8 : -8;

    grid[to_sq] = piece;
    zhash ^= zobrist.piece_square[piece + 9][tr][tc];
    zhash ^= zobrist.turn;
    turn = -turn;

    if (std::abs(he.piece) == 2)
    {
        if (he.piece > 0)
            wking_sq = to_sq;
        else
            bking_sq = to_sq;
    }
    if (std::abs(he.captured) == 2)
    {
        if (he.captured > 0)
            wking_sq = -1;
        else
            bking_sq = -1;
    }
}

void FastBoard::unmake_move()
{
    if (history.empty())
        return;
    HistoryEntry he = history.back();
    history.pop_back();
    turn = -turn;
    grid[he.from_sq] = he.piece;
    grid[he.to_sq] = he.captured;
    zhash = he.old_hash;

    if (std::abs(he.piece) == 2)
    {
        if (he.piece > 0)
            wking_sq = he.from_sq;
        else
            bking_sq = he.from_sq;
    }
    if (std::abs(he.captured) == 2)
    {
        if (he.captured > 0)
            wking_sq = he.to_sq;
        else
            bking_sq = he.to_sq;
    }
}

bool FastBoard::is_in_check(int8_t color) const
{
    int king_sq = (color == 1) ? wking_sq : bking_sq;
    if (king_sq < 0)
        return false;
    int kr = row(king_sq), kc = col(king_sq);
    for (int r = 0; r < BOARD_SIZE; ++r)
        for (int c = 0; c < BOARD_SIZE; ++c)
        {
            int p = grid[sq(r, c)];
            if (p == 0 || (p > 0) == (color > 0))
                continue;
            if (MoveGenerator::piece_attacks(*this, r, c, kr, kc, p))
                return true;
        }
    return false;
}

bool FastBoard::is_insufficient_material() const
{
    int count = 0, knights = 0;
    for (int i = 0; i < TOTAL_SQUARES; ++i)
    {
        int p = std::abs(grid[i]);
        if (p)
        {
            ++count;
            if (p == 3)
                ++knights;
        }
    }
    return (count == 2) || (count == 3 && knights == 1);
}

// ═══════════════════════════════════════════════════════════════
// Move Generator
// ═══════════════════════════════════════════════════════════════
static const int KNIGHT_MOVES[8][2] = {{2, 1}, {2, -1}, {-2, 1}, {-2, -1}, {1, 2}, {1, -2}, {-1, 2}, {-1, -2}};
static const int EXT_KNIGHT_MOVES[8][2] = {{3, 1}, {3, -1}, {-3, 1}, {-3, -1}, {1, 3}, {1, -3}, {-1, 3}, {-1, -3}};
static const int KING_STEPS[8][2] = {{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1}};
static const int ORTH[4][2] = {{0, 1}, {0, -1}, {1, 0}, {-1, 0}};
static const int DIAG[4][2] = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}};

uint32_t MoveGenerator::pack_move(int fr, int fc, int tr, int tc, int captured)
{
    return (fr & 0x7) | ((fc & 0x7) << 3) | ((tr & 0x7) << 6) | ((tc & 0x7) << 9) | ((captured & 0x3F) << 12);
}

void MoveGenerator::unpack_move(uint32_t move, int &fr, int &fc, int &tr, int &tc, int &captured)
{
    fr = move & 0x7;
    fc = (move >> 3) & 0x7;
    tr = (move >> 6) & 0x7;
    tc = (move >> 9) & 0x7;
    captured = (move >> 12) & 0x3F;
    if (captured >= 32)
        captured -= 64;
}

void MoveGenerator::try_add(const FastBoard &fb, int r, int c, int nr, int nc, int p,
                            std::vector<uint32_t> &moves)
{
    if (nr < 0 || nr >= BOARD_SIZE || nc < 0 || nc >= BOARD_SIZE)
        return;
    int t = fb.grid[FastBoard::sq(nr, nc)];
    if (t == 0 || (t > 0) != (p > 0))
        moves.push_back(pack_move(r, c, nr, nc, t));
}

void MoveGenerator::slide(const FastBoard &fb, int r, int c, int dr, int dc, int p,
                          std::vector<uint32_t> &moves)
{
    int nr = r + dr, nc = c + dc;
    while (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
    {
        int t = fb.grid[FastBoard::sq(nr, nc)];
        if (t == 0)
            moves.push_back(pack_move(r, c, nr, nc, 0));
        else
        {
            if ((t > 0) != (p > 0))
                moves.push_back(pack_move(r, c, nr, nc, t));
            break;
        }
        nr += dr;
        nc += dc;
    }
}

void MoveGenerator::add_piece_moves(const FastBoard &fb, int r, int c, int p,
                                    std::vector<uint32_t> &moves)
{
    int pt = std::abs(p);
    switch (pt)
    {
    case 2:
        for (auto &s : KING_STEPS)
            try_add(fb, r, c, r + s[0], c + s[1], p, moves);
        break;
    case 3:
        for (auto &m : KNIGHT_MOVES)
            try_add(fb, r, c, r + m[0], c + m[1], p, moves);
        break;
    case 4:
        for (auto &d : DIAG)
            slide(fb, r, c, d[0], d[1], p, moves);
        for (auto &o : ORTH)
            try_add(fb, r, c, r + o[0], c + o[1], p, moves);
        break;
    case 5:
        for (auto &m : EXT_KNIGHT_MOVES)
            try_add(fb, r, c, r + m[0], c + m[1], p, moves);
        for (auto &o : ORTH)
            try_add(fb, r, c, r + o[0], c + o[1], p, moves);
        break;
    case 6:
        for (auto &o : ORTH)
            slide(fb, r, c, o[0], o[1], p, moves);
        for (auto &m : KNIGHT_MOVES)
            try_add(fb, r, c, r + m[0], c + m[1], p, moves);
        break;
    case 7:
    {
        int fwd = (p > 0) ? 1 : -1;
        for (int dc : {-1, 1})
        {
            int nr = r + fwd, nc = c + dc;
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE && fb.grid[FastBoard::sq(nr, nc)] == 0)
                moves.push_back(pack_move(r, c, nr, nc, 0));
        }
        int nr = r + fwd;
        if (nr >= 0 && nr < BOARD_SIZE)
        {
            int t = fb.grid[FastBoard::sq(nr, c)];
            if (t != 0 && (t > 0) != (p > 0))
                moves.push_back(pack_move(r, c, nr, c, t));
        }
        break;
    }
    case 8:
        for (int dr = -2; dr <= 2; ++dr)
            for (int dc = -2; dc <= 2; ++dc)
                if (std::max(std::abs(dr), std::abs(dc)) == 2)
                    try_add(fb, r, c, r + dr, c + dc, p, moves);
        break;
    case 9:
        for (int dr = -2; dr <= 2; ++dr)
            for (int dc = -2; dc <= 2; ++dc)
                if (std::abs(dr) + std::abs(dc) == 1 || std::abs(dr) + std::abs(dc) == 2)
                    try_add(fb, r, c, r + dr, c + dc, p, moves);
        break;
    }
}

std::vector<uint32_t> MoveGenerator::generate_piece_attack_squares(const FastBoard &fb, int r, int c)
{
    std::vector<uint32_t> moves;
    if (r < 0 || r >= BOARD_SIZE || c < 0 || c >= BOARD_SIZE)
        return moves;
    int p = fb.grid[FastBoard::sq(r, c)];
    if (p == 0)
        return moves;
    int pt = std::abs(p);

    switch (pt)
    {
    case 2:
        for (auto &s : KING_STEPS)
        {
            int nr = r + s[0], nc = c + s[1];
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
        }
        break;
    case 3:
        for (auto &m : KNIGHT_MOVES)
        {
            int nr = r + m[0], nc = c + m[1];
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
        }
        break;
    case 4:
        for (auto &d : DIAG)
        {
            int nr = r + d[0], nc = c + d[1];
            while (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
            {
                int t = fb.grid[FastBoard::sq(nr, nc)];
                moves.push_back(pack_move(r, c, nr, nc, t));
                if (t)
                    break;
                nr += d[0];
                nc += d[1];
            }
        }
        for (auto &o : ORTH)
        {
            int nr = r + o[0], nc = c + o[1];
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
        }
        break;
    case 5:
        for (auto &m : EXT_KNIGHT_MOVES)
        {
            int nr = r + m[0], nc = c + m[1];
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
        }
        for (auto &o : ORTH)
        {
            int nr = r + o[0], nc = c + o[1];
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
        }
        break;
    case 6:
        for (auto &o : ORTH)
        {
            int nr = r + o[0], nc = c + o[1];
            while (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
            {
                int t = fb.grid[FastBoard::sq(nr, nc)];
                moves.push_back(pack_move(r, c, nr, nc, t));
                if (t)
                    break;
                nr += o[0];
                nc += o[1];
            }
        }
        for (auto &m : KNIGHT_MOVES)
        {
            int nr = r + m[0], nc = c + m[1];
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
        }
        break;
    case 7:
    {
        int fwd = (p > 0) ? 1 : -1;
        for (int dc : {-1, 1})
        {
            int nr = r + fwd, nc = c + dc;
            if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE && fb.grid[FastBoard::sq(nr, nc)] == 0)
                moves.push_back(pack_move(r, c, nr, nc, 0));
        }
        int nr = r + fwd;
        if (nr >= 0 && nr < BOARD_SIZE)
        {
            int t = fb.grid[FastBoard::sq(nr, c)];
            if (t != 0 && (t > 0) != (p > 0))
                moves.push_back(pack_move(r, c, nr, c, t));
        }
        break;
    }
    case 8:
        for (int dr = -2; dr <= 2; ++dr)
            for (int dc = -2; dc <= 2; ++dc)
                if (std::max(std::abs(dr), std::abs(dc)) == 2)
                {
                    int nr = r + dr, nc = c + dc;
                    if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                        moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
                }
        break;
    case 9:
        for (int dr = -2; dr <= 2; ++dr)
            for (int dc = -2; dc <= 2; ++dc)
                if (std::abs(dr) + std::abs(dc) == 1 || std::abs(dr) + std::abs(dc) == 2)
                {
                    int nr = r + dr, nc = c + dc;
                    if (nr >= 0 && nr < BOARD_SIZE && nc >= 0 && nc < BOARD_SIZE)
                        moves.push_back(pack_move(r, c, nr, nc, fb.grid[FastBoard::sq(nr, nc)]));
                }
        break;
    }
    return moves;
}

std::vector<uint32_t> MoveGenerator::generate_piece_pseudo_moves(const FastBoard &fb, int r, int c)
{
    std::vector<uint32_t> moves;
    if (r < 0 || r >= BOARD_SIZE || c < 0 || c >= BOARD_SIZE)
        return moves;
    int p = fb.grid[FastBoard::sq(r, c)];
    if (p == 0)
        return moves;
    add_piece_moves(fb, r, c, p, moves);
    return moves;
}

std::vector<uint32_t> MoveGenerator::generate_pseudo_moves(const FastBoard &fb)
{
    std::vector<uint32_t> moves;
    moves.reserve(64);
    for (int r = 0; r < BOARD_SIZE; ++r)
        for (int c = 0; c < BOARD_SIZE; ++c)
        {
            int p = fb.grid[FastBoard::sq(r, c)];
            if (p == 0 || (p > 0) != (fb.turn > 0))
                continue;
            add_piece_moves(fb, r, c, p, moves);
        }
    return moves;
}

std::vector<uint32_t> MoveGenerator::generate_legal_moves(const FastBoard &fb)
{
    std::vector<uint32_t> legal;
    auto pseudo = generate_pseudo_moves(fb);

    // Lightweight scratch board — no history copy (we only need grid/turn/kings)
    FastBoard temp;
    temp.grid = fb.grid;
    temp.turn = fb.turn;
    temp.zhash = fb.zhash;
    temp.wking_sq = fb.wking_sq;
    temp.bking_sq = fb.bking_sq;

    for (uint32_t move : pseudo)
    {
        int fr, fc, tr, tc, captured;
        unpack_move(move, fr, fc, tr, tc, captured);
        if (std::abs(captured) == 2)
            continue; // capturing a king is illegal

        int8_t piece = temp.grid[FastBoard::sq(fr, fc)];
        int8_t target = temp.grid[FastBoard::sq(tr, tc)];

        temp.grid[FastBoard::sq(fr, fc)] = 0;
        int8_t moved = piece;
        if (std::abs(piece) == 7)
            if ((piece > 0 && tr == 6) || (piece < 0 && tr == 0))
                moved = (piece > 0) ? 8 : -8;
        temp.grid[FastBoard::sq(tr, tc)] = moved;
        temp.turn = -temp.turn;

        int owk = temp.wking_sq, obk = temp.bking_sq;
        if (std::abs(piece) == 2)
        {
            if (piece > 0)
                temp.wking_sq = FastBoard::sq(tr, tc);
            else
                temp.bking_sq = FastBoard::sq(tr, tc);
        }
        if (std::abs(target) == 2)
        {
            if (target > 0)
                temp.wking_sq = -1;
            else
                temp.bking_sq = -1;
        }

        if (!temp.is_in_check(-temp.turn))
            legal.push_back(move);

        // Restore scratch board
        temp.turn = -temp.turn;
        temp.grid[FastBoard::sq(fr, fc)] = piece;
        temp.grid[FastBoard::sq(tr, tc)] = target;
        temp.wking_sq = owk;
        temp.bking_sq = obk;
    }
    return legal;
}

std::vector<uint32_t> MoveGenerator::generate_captures(const FastBoard &fb)
{
    std::vector<uint32_t> caps;
    for (uint32_t move : generate_pseudo_moves(fb))
    {
        int fr, fc, tr, tc, cap;
        unpack_move(move, fr, fc, tr, tc, cap);
        if (cap != 0 && std::abs(cap) != 2)
            caps.push_back(move);
    }
    return caps;
}

bool MoveGenerator::piece_attacks(const FastBoard &fb, int fr, int fc, int tr, int tc, int pc)
{
    int dr = tr - fr, dc = tc - fc, adr = std::abs(dr), adc = std::abs(dc), pt = std::abs(pc);
    switch (pt)
    {
    case 2:
        return std::max(adr, adc) == 1;
    case 3:
        return (adr == 2 && adc == 1) || (adr == 1 && adc == 2);
    case 4:
    {
        if (adr == adc && dr != 0)
        {
            int sr = (dr > 0) ? 1 : -1, sc = (dc > 0) ? 1 : -1, r = fr + sr, c = fc + sc;
            while (r != tr || c != tc)
            {
                if (fb.grid[FastBoard::sq(r, c)])
                    return false;
                r += sr;
                c += sc;
            }
            return true;
        }
        return (adr == 1 && adc == 0) || (adr == 0 && adc == 1);
    }
    case 5:
        return ((adr == 3 && adc == 1) || (adr == 1 && adc == 3)) || (adr + adc == 1);
    case 6:
    {
        if ((dr == 0) != (dc == 0))
        {
            int sr = (dr == 0) ? 0 : (dr > 0 ? 1 : -1), sc = (dc == 0) ? 0 : (dc > 0 ? 1 : -1), r = fr + sr, c = fc + sc;
            while (r != tr || c != tc)
            {
                if (fb.grid[FastBoard::sq(r, c)])
                    return false;
                r += sr;
                c += sc;
            }
            return true;
        }
        return (adr == 2 && adc == 1) || (adr == 1 && adc == 2);
    }
    case 7:
    {
        int fwd = (pc > 0) ? 1 : -1;
        return dr == fwd && dc == 0;
    }
    case 8:
        return std::max(adr, adc) == 2;
    case 9:
        return (adr + adc == 1) || (adr + adc == 2);
    }
    return false;
}

// ═══════════════════════════════════════════════════════════════
// Evaluator — PST tables (identical to v1)
// ═══════════════════════════════════════════════════════════════
const int Evaluator::PST_MG_W[7][7] = {{0, 5, 10, 15, 10, 5, 0}, {5, 15, 25, 30, 25, 15, 5}, {10, 25, 40, 45, 40, 25, 10}, {15, 30, 45, 55, 45, 30, 15}, {25, 40, 55, 60, 55, 40, 25}, {35, 50, 65, 70, 65, 50, 35}, {45, 60, 75, 80, 75, 60, 45}};
const int Evaluator::PST_MG_B[7][7] = {{45, 60, 75, 80, 75, 60, 45}, {35, 50, 65, 70, 65, 50, 35}, {25, 40, 55, 60, 55, 40, 25}, {15, 30, 45, 55, 45, 30, 15}, {10, 25, 40, 45, 40, 25, 10}, {5, 15, 25, 30, 25, 15, 5}, {0, 5, 10, 15, 10, 5, 0}};
const int Evaluator::PST_EG_W[7][7] = {{-5, 0, 5, 8, 5, 0, -5}, {0, 8, 15, 18, 15, 8, 0}, {5, 15, 28, 32, 28, 15, 5}, {8, 18, 32, 38, 32, 18, 8}, {18, 28, 42, 46, 42, 28, 18}, {28, 38, 52, 56, 52, 38, 28}, {38, 48, 62, 66, 62, 48, 38}};
const int Evaluator::PST_EG_B[7][7] = {{38, 48, 62, 66, 62, 48, 38}, {28, 38, 52, 56, 52, 38, 28}, {18, 28, 42, 46, 42, 28, 18}, {8, 18, 32, 38, 32, 18, 8}, {5, 15, 28, 32, 28, 15, 5}, {0, 8, 15, 18, 15, 8, 0}, {-5, 0, 5, 8, 5, 0, -5}};
const int Evaluator::KING_MG_W[7][7] = {{30, 20, 0, -20, 0, 20, 30}, {10, 0, -20, -40, -20, 0, 10}, {-10, -20, -40, -60, -40, -20, -10}, {-30, -40, -60, -80, -60, -40, -30}, {-50, -60, -80, -100, -80, -60, -50}, {-70, -80, -100, -120, -100, -80, -70}, {-90, -100, -120, -140, -120, -100, -90}};
const int Evaluator::KING_MG_B[7][7] = {{-90, -100, -120, -140, -120, -100, -90}, {-70, -80, -100, -120, -100, -80, -70}, {-50, -60, -80, -100, -80, -60, -50}, {-30, -40, -60, -80, -60, -40, -30}, {-10, -20, -40, -60, -40, -20, -10}, {10, 0, -20, -40, -20, 0, 10}, {30, 20, 0, -20, 0, 20, 30}};
const int Evaluator::KING_EG_W[7][7] = {{-20, -10, 0, 10, 0, -10, -20}, {-10, 0, 10, 20, 10, 0, -10}, {0, 10, 25, 30, 25, 10, 0}, {10, 20, 30, 40, 30, 20, 10}, {0, 10, 25, 30, 25, 10, 0}, {-10, 0, 10, 20, 10, 0, -10}, {-20, -10, 0, 10, 0, -10, -20}};
const int Evaluator::KING_EG_B[7][7] = {{-20, -10, 0, 10, 0, -10, -20}, {-10, 0, 10, 20, 10, 0, -10}, {0, 10, 25, 30, 25, 10, 0}, {10, 20, 30, 40, 30, 20, 10}, {0, 10, 25, 30, 25, 10, 0}, {-10, 0, 10, 20, 10, 0, -10}, {-20, -10, 0, 10, 0, -10, -20}};

// ─── New eval helpers ────────────────────────────────────────────

bool Evaluator::is_passed_donkey(const FastBoard &fb, int r, int c, int p)
{
    int fwd = (p > 0) ? 1 : -1;
    int8_t enemy_dk = (p > 0) ? -7 : 7;
    for (int nr = r + fwd; nr >= 0 && nr < BOARD_SIZE; nr += fwd)
        if (fb.grid[FastBoard::sq(nr, c)] == enemy_dk)
            return false;
    return true;
}

bool Evaluator::is_outpost(const FastBoard &fb, int r, int c, int color)
{
    // An outpost is a square where no enemy donkey can ever reach to attack.
    // Enemy donkeys attack straight forward; they advance from their side.
    int8_t edk = (color > 0) ? -7 : 7; // enemy donkey code
    int efwd = (color > 0) ? -1 : 1;   // direction enemy donkeys move

    // For files c-1, c, c+1: check if any enemy donkey stands behind and
    // could advance to attack (r, c) diagonally (i.e., at c±1 from the dk file).
    for (int fc2 = c - 1; fc2 <= c + 1; ++fc2)
    {
        if (fc2 < 0 || fc2 >= BOARD_SIZE)
            continue;
        for (int er = 0; er < BOARD_SIZE; ++er)
        {
            if (fb.grid[FastBoard::sq(er, fc2)] != edk)
                continue;
            // Can this donkey reach a square that attacks (r,c)?
            // Donkey attacks (r,c) diagonally from (r - efwd, c±1).
            // Attack source must be on an adjacent file to c.
            int attack_r = r - efwd; // row from which enemy donkey would attack
            if (attack_r < 0 || attack_r >= BOARD_SIZE)
                continue;
            // The attacking donkey file must be ±1 from c
            if (std::abs(fc2 - c) == 1)
            {
                // Can the enemy donkey at (er,fc2) advance to (attack_r, fc2)?
                // It can if its path is clear (simplified: we just check it exists
                // on the right side). For outpost purposes this is sufficient.
                bool path_clear = true;
                int step = efwd;
                for (int nr = er + step; nr != attack_r; nr += step)
                {
                    if (nr < 0 || nr >= BOARD_SIZE)
                    {
                        path_clear = false;
                        break;
                    }
                    if (fb.grid[FastBoard::sq(nr, fc2)] != 0)
                    {
                        path_clear = false;
                        break;
                    }
                }
                if (path_clear)
                    return false; // enemy can reach attack square
            }
        }
    }
    return true;
}

int Evaluator::king_structure(const FastBoard &fb, int kr, int kc, int color, float phase)
{
    int score = 0;
    int8_t friend_dk = (color > 0) ? 7 : -7;

    for (int fc = std::max(0, kc - 1); fc <= std::min(BOARD_SIZE - 1, kc + 1); ++fc)
    {
        bool has_donkey = false;
        bool has_friendly = false;
        for (int r2 = 0; r2 < BOARD_SIZE; ++r2)
        {
            int p2 = fb.grid[FastBoard::sq(r2, fc)];
            if (p2 == friend_dk)
                has_donkey = true;
            if (p2 != 0 && (p2 > 0) == (color > 0) && std::abs(p2) != 2)
                has_friendly = true;
        }
        if (!has_donkey)
            score -= lerp(KING_OPEN_FILE_PEN_MG, KING_OPEN_FILE_PEN_EG, phase);
        if (has_friendly)
            score += lerp(KING_SHIELD_BONUS_MG, KING_SHIELD_BONUS_EG, phase);
    }
    return score;
}

float Evaluator::compute_phase(const FastBoard &fb)
{
    int ps = 0;
    for (int i = 0; i < TOTAL_SQUARES; ++i)
    {
        int p = fb.grid[i];
        if (p)
            ps += PHASE_WEIGHTS[std::abs(p)];
    }
    return std::min(1.0f, static_cast<float>(ps) / TOTAL_MAX_PHASE);
}

int Evaluator::count_pseudo_mobility(const FastBoard &fb, int r, int c, int p)
{
    std::vector<uint32_t> moves;
    MoveGenerator::add_piece_moves(fb, r, c, p, moves);
    return static_cast<int>(moves.size());
}

int Evaluator::king_escape_score(const FastBoard &fb, int kr, int kc, int color)
{
    int safe = 0;
    for (auto &s : KING_STEPS)
    {
        int nr = kr + s[0], nc = kc + s[1];
        if (nr < 0 || nr >= BOARD_SIZE || nc < 0 || nc >= BOARD_SIZE)
            continue;
        int target = fb.grid[FastBoard::sq(nr, nc)];
        if (target != 0 && (target > 0) == (color > 0))
            continue;
        bool attacked = false;
        for (int r2 = 0; r2 < BOARD_SIZE && !attacked; ++r2)
            for (int c2 = 0; c2 < BOARD_SIZE; ++c2)
            {
                int p2 = fb.grid[FastBoard::sq(r2, c2)];
                if (p2 == 0 || (p2 > 0) == (color > 0))
                    continue;
                if (MoveGenerator::piece_attacks(fb, r2, c2, nr, nc, p2))
                {
                    attacked = true;
                    break;
                }
            }
        if (!attacked)
            ++safe;
    }
    return safe;
}

int Evaluator::king_danger(const FastBoard &fb, int king_r, int king_c, int attacker_sign)
{
    int danger = 0, attackers_near = 0;
    for (int r = 0; r < BOARD_SIZE; ++r)
        for (int c = 0; c < BOARD_SIZE; ++c)
        {
            int p = fb.grid[FastBoard::sq(r, c)];
            if (p == 0 || (p > 0) != (attacker_sign > 0))
                continue;
            int pt = std::abs(p);
            if (pt == 2)
                continue;
            int dist = std::max(std::abs(r - king_r), std::abs(c - king_c));
            if (dist <= 3)
            {
                int w = TROPISM_WEIGHTS[pt];
                danger += (dist == 1) ? w * 4 : (dist == 2) ? w * 2
                                                            : w;
            }
            if (dist <= 4)
                for (int dr = -1; dr <= 1; ++dr)
                    for (int dc = -1; dc <= 1; ++dc)
                    {
                        int tr_ = king_r + dr, tc_ = king_c + dc;
                        if (tr_ < 0 || tr_ >= BOARD_SIZE || tc_ < 0 || tc_ >= BOARD_SIZE)
                            continue;
                        if (MoveGenerator::piece_attacks(fb, r, c, tr_, tc_, p))
                            ++attackers_near;
                    }
        }
    danger += attackers_near * attackers_near * 3;
    return danger;
}

int Evaluator::see(const FastBoard &fb, uint32_t move)
{
    int fr, fc, tr, tc, captured;
    MoveGenerator::unpack_move(move, fr, fc, tr, tc, captured);
    if (captured == 0)
        return 0;

    FastBoard sb = fb;
    int gain[32];
    int d = 0;
    int attacker = sb.grid[FastBoard::sq(fr, fc)];
    int victim = sb.grid[FastBoard::sq(tr, tc)];
    sb.grid[FastBoard::sq(fr, fc)] = 0;

    int victim_val = PIECE_VALUES[std::abs(victim)];
    if (std::abs(attacker) == 7)
        if ((attacker > 0 && tr == 6) || (attacker < 0 && tr == 0))
        {
            victim_val += PIECE_VALUES[8] - PIECE_VALUES[7];
            attacker = (attacker > 0) ? 8 : -8;
        }
    sb.grid[FastBoard::sq(tr, tc)] = attacker;
    gain[d] = victim_val;
    int side = (attacker > 0) ? -1 : 1;

    while (true)
    {
        int lva_r = -1, lva_c = -1, lva_val = 999999, lva_piece = 0;
        for (int r = 0; r < BOARD_SIZE; ++r)
            for (int c = 0; c < BOARD_SIZE; ++c)
            {
                int p = sb.grid[FastBoard::sq(r, c)];
                if (!p || (p > 0) != (side > 0))
                    continue;
                if (MoveGenerator::piece_attacks(sb, r, c, tr, tc, p))
                {
                    int v = PIECE_VALUES[std::abs(p)];
                    if (v < lva_val)
                    {
                        lva_val = v;
                        lva_r = r;
                        lva_c = c;
                        lva_piece = p;
                    }
                }
            }
        if (lva_r == -1)
            break;
        ++d;
        victim = sb.grid[FastBoard::sq(tr, tc)];
        victim_val = PIECE_VALUES[std::abs(victim)];
        if (std::abs(lva_piece) == 7)
            if ((lva_piece > 0 && tr == 6) || (lva_piece < 0 && tr == 0))
            {
                victim_val += PIECE_VALUES[8] - PIECE_VALUES[7];
                lva_piece = (lva_piece > 0) ? 8 : -8;
            }
        gain[d] = victim_val - gain[d - 1];
        sb.grid[FastBoard::sq(lva_r, lva_c)] = 0;
        sb.grid[FastBoard::sq(tr, tc)] = lva_piece;
        side = -side;
        if (d >= 31)
            break;
    }
    while (d > 0)
    {
        --d;
        gain[d] = -std::max(-gain[d], gain[d + 1]);
    }
    return gain[0];
}

int Evaluator::evaluate(const FastBoard &fb, int halfmove_clock)
{
    if (fb.is_insufficient_material() || halfmove_clock >= 40)
        return 0;

    float phase = compute_phase(fb);
    int score = 0;
    int wkr = -1, wkc = -1, bkr = -1, bkc = -1;

    for (int r = 0; r < BOARD_SIZE; ++r)
        for (int c = 0; c < BOARD_SIZE; ++c)
        {
            int p = fb.grid[FastBoard::sq(r, c)];
            if (!p)
                continue;
            int pt = std::abs(p), base = PIECE_VALUES[pt];
            if (pt == 2)
            {
                if (p > 0)
                {
                    wkr = r;
                    wkc = c;
                }
                else
                {
                    bkr = r;
                    bkc = c;
                }
                continue;
            }

            int pst = (p > 0) ? lerp(PST_MG_W[r][c], PST_EG_W[r][c], phase)
                              : lerp(PST_MG_B[r][c], PST_EG_B[r][c], phase);

            int adv = 0;
            if (pt == 7)
            {
                int amg = (p > 0) ? r * (DONKEY_ADV_MG) : (6 - r) * (DONKEY_ADV_MG);
                int aeg = (p > 0) ? r * (DONKEY_ADV_EG) : (6 - r) * (DONKEY_ADV_EG);
                adv = lerp(amg, aeg, phase);
                if (is_passed_donkey(fb, r, c, p))
                    adv += lerp(PASSED_DONKEY_MG, PASSED_DONKEY_EG, phase);
            }

            int outpost = 0;
            if ((pt == 3 || pt == 5) && is_outpost(fb, r, c, (p > 0) ? 1 : -1))
                outpost = lerp(OUTPOST_MG, OUTPOST_EG, phase);

            int mob = count_pseudo_mobility(fb, r, c, p);
            int mob_bonus = lerp(mob * MOBILITY_WEIGHT_MG * MOBILITY_MULT_MG[pt],
                                 mob * MOBILITY_WEIGHT_EG * MOBILITY_MULT_EG[pt], phase);
            int trapped = (mob <= 1)   ? lerp(TRAPPED_PENALTY_MG, TRAPPED_PENALTY_EG, phase)
                          : (mob == 2) ? lerp(CRAMPED_PENALTY_MG, CRAMPED_PENALTY_EG, phase)
                                       : 0;

            int piece_total = base + pst + adv + outpost;
            if (p > 0)
                score += piece_total + mob_bonus - trapped;
            else
            {
                score -= piece_total + mob_bonus;
                score += trapped;
            }
        }

    if (wkr >= 0)
        score += lerp(KING_MG_W[wkr][wkc], KING_EG_W[wkr][wkc], phase);
    if (bkr >= 0)
        score -= lerp(KING_MG_B[bkr][bkc], KING_EG_B[bkr][bkc], phase);

    float ds = phase * KING_DANGER_SCALE_MG + (1.0f - phase) * KING_DANGER_SCALE_EG;
    if (wkr >= 0)
        score -= static_cast<int>(king_danger(fb, wkr, wkc, -1) * ds);
    if (bkr >= 0)
        score += static_cast<int>(king_danger(fb, bkr, bkc, 1) * ds);

    if (wkr >= 0)
    {
        int e = king_escape_score(fb, wkr, wkc, 1);
        int i = std::min(e, 8);
        score -= lerp(ESCAPE_PENALTY_MG[i], ESCAPE_PENALTY_EG[i], phase);
    }
    if (bkr >= 0)
    {
        int e = king_escape_score(fb, bkr, bkc, -1);
        int i = std::min(e, 8);
        score += lerp(ESCAPE_PENALTY_MG[i], ESCAPE_PENALTY_EG[i], phase);
    }

    if (wkr >= 0)
        score += king_structure(fb, wkr, wkc, 1, phase);
    if (bkr >= 0)
        score -= king_structure(fb, bkr, bkc, -1, phase);

    if (fb.is_in_check(1))
        score -= 150;
    if (fb.is_in_check(-1))
        score += 150;
    score += (fb.turn == 1) ? TEMPO_BONUS : -TEMPO_BONUS;

    return (fb.turn == 1) ? score : -score;
}

// ═══════════════════════════════════════════════════════════════
// Searcher
// ═══════════════════════════════════════════════════════════════
Searcher::Searcher() : tt_age(0)
{
    timed_out.store(false);
    atomic_best_move.store(0);
    atomic_best_score.store(0);
    atomic_total_nodes.store(0);
    shared_tt.clear();
}

void Searcher::clear_tables()
{
    shared_tt.clear();
    tt_age = 0;
}

String Searcher::format_mate(int white_score)
{
    if (white_score > MATE_SCORE - 1000)
    {
        int p = MATE_SCORE - white_score;
        return String("M") + String::num_int64(std::max(1, (p + 1) / 2));
    }
    if (white_score < -MATE_SCORE + 1000)
    {
        int p = MATE_SCORE + white_score;
        return String("-M") + String::num_int64(std::max(1, (p + 1) / 2));
    }
    return "";
}

// ─── Move ordering ─────────────────────────────────────────────
std::vector<uint32_t> Searcher::order_moves(FastBoard &fb,
                                            const std::vector<uint32_t> &moves, int ply,
                                            uint32_t tt_move, uint32_t countermove, ThreadData &td)
{
    struct SM
    {
        int score;
        uint32_t move;
    };
    std::vector<SM> scored;
    scored.reserve(moves.size());

    for (uint32_t move : moves)
    {
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        int p = fb.grid[FastBoard::sq(fr, fc)];
        int pt = std::abs(p);
        int s = 0;

        if (move == tt_move)
            s = 2'000'000;
        else if (cap != 0)
        {
            int see_val = Evaluator::see(fb, move);
            if (see_val >= 0)
                // Within winning captures use MVV-LVA for a free, stable ordering
                s = 1'000'000 + mvv_lva(std::abs(cap), pt);
            else
                // Losing captures go below quiets, ordered by SEE
                s = -200'000 + see_val;
        }
        else if (pt == 7 && ((p > 0 && tr == 6) || (p < 0 && tr == 0)))
            s = 900'000; // promotion
        else if (move == countermove)
            s = 850'000;
        else if (td.killers[ply][0] == move)
            s = 800'000;
        else if (td.killers[ply][1] == move)
            s = 700'000;
        else
        {
            s = td.history[fr][fc][tr][tc];
            if (!fb.history.empty())
            {
                const auto &he = fb.history.back();
                int ppt = std::abs(he.piece), pto = he.to_sq;
                s += td.cont_history[ppt][pto][FastBoard::sq(fr, fc)][FastBoard::sq(tr, tc)];
            }
            if (2 <= tr && tr <= 4 && 2 <= tc && tc <= 4)
                s += 20; // centre bonus
        }
        scored.push_back({s, move});
    }

    std::sort(scored.begin(), scored.end(),
              [](const SM &a, const SM &b)
              { return a.score > b.score; });

    std::vector<uint32_t> out;
    out.reserve(scored.size());
    for (auto &sm : scored)
        out.push_back(sm.move);
    return out;
}

// ─── Quiescence ────────────────────────────────────────────────
int Searcher::quiescence(FastBoard &fb, int alpha, int beta, int ply, int hm, ThreadData &td)
{
    if (ply >= MAX_PLY)
        return Evaluator::evaluate(fb, hm);
    if (hm >= 40)
        return 0;
    if (timed_out.load(std::memory_order_relaxed))
        return 0;

    ++td.nodes;
    td.maybe_apply_gravity();

    bool in_check = fb.is_in_check(fb.turn);

    if (in_check)
    {
        auto pseudo = MoveGenerator::generate_pseudo_moves(fb);
        int best = -MATE_SCORE, legal = 0;
        for (uint32_t move : pseudo)
        {
            if ((td.nodes & 15) == 0 && std::chrono::steady_clock::now() > deadline)
            {
                timed_out.store(true, std::memory_order_relaxed);
                return best;
            }

            int fr, fc, tr, tc, cap;
            MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
            if (std::abs(cap) == 2)
                continue;

            int8_t pb = fb.grid[FastBoard::sq(fr, fc)];
            bool isd = (std::abs(pb) == 7);
            int chm = (cap || isd) ? 0 : hm + 1;

            fb.make_move(move, zobrist);
            if (fb.is_in_check(-fb.turn))
            {
                fb.unmake_move();
                continue;
            }
            ++legal;
            int val = -quiescence(fb, -beta, -alpha, ply + 1, chm, td);
            fb.unmake_move();

            if (val > best)
                best = val;
            if (val > alpha)
                alpha = val;
            if (alpha >= beta)
                return best;
        }
        if (legal == 0)
            return -MATE_SCORE + ply;
        return best;
    }

    int stand_pat = Evaluator::evaluate(fb, hm);
    if (stand_pat >= beta)
        return stand_pat;
    int best = stand_pat;
    if (stand_pat > alpha)
        alpha = stand_pat;
    if (stand_pat + 900 < alpha)
        return stand_pat; // delta pruning

    auto caps = MoveGenerator::generate_captures(fb);
    if (caps.empty())
        return stand_pat;
    auto ordered = order_moves(fb, caps, std::min(ply, 63), 0, 0, td);

    for (uint32_t move : ordered)
    {
        if ((td.nodes & 15) == 0 && std::chrono::steady_clock::now() > deadline)
        {
            timed_out.store(true, std::memory_order_relaxed);
            return best;
        }

        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        int8_t pb = fb.grid[FastBoard::sq(fr, fc)];
        bool isd = (std::abs(pb) == 7);

        if (Evaluator::see(fb, move) < 0 && stand_pat + Evaluator::see(fb, move) + 50 < alpha)
            continue;

        int chm = (cap || isd) ? 0 : hm + 1;
        fb.make_move(move, zobrist);
        if (fb.is_in_check(-fb.turn))
        {
            fb.unmake_move();
            continue;
        }
        int val = -quiescence(fb, -beta, -alpha, ply + 1, chm, td);
        fb.unmake_move();

        if (val > best)
            best = val;
        if (val > alpha)
            alpha = val;
        if (alpha >= beta)
            return best;
    }
    return best;
}

// ─── Negamax ───────────────────────────────────────────────────
int Searcher::negamax(FastBoard &fb, int depth, int alpha, int beta, int ply,
                      bool allow_null, int wp, int bp, int extensions, int hm,
                      ThreadData &td)
{
    if (ply >= MAX_PLY)
        return Evaluator::evaluate(fb, hm);
    if (fb.is_insufficient_material() || hm >= 40)
        return 0;
    if (timed_out.load(std::memory_order_relaxed))
        return 0;

    ++td.nodes;
    td.maybe_apply_gravity();

    alpha = std::max(alpha, -MATE_SCORE + ply);
    beta = std::min(beta, MATE_SCORE - ply - 1);
    if (alpha >= beta)
        return alpha;

    // Prefetch TT bucket before the probe (hides latency)
    shared_tt.prefetch(fb.zhash);

    uint64_t key = fb.zhash ^ zobrist.hm_key(hm);
    uint32_t tt_move = 0;
    int tt_score = 0;
    TTFlag tt_flag = TT_NONE;
    bool tt_hit = shared_tt.probe(key, depth, alpha, beta, ply, tt_move, tt_score, tt_flag);
    if (tt_hit)
        return tt_score;

    // IID: no TT move at depth >= 4 → search one ply shallower to get one
    if (tt_move == 0 && depth >= 4)
        --depth;
    if (depth <= 0)
        return quiescence(fb, alpha, beta, ply, hm, td);

    bool in_check = fb.is_in_check(fb.turn);
    bool near_mate = (std::abs(alpha) >= NEAR_MATE || std::abs(beta) >= NEAR_MATE);

    int static_eval = 0;
    bool improving = false;
    if (!in_check && !near_mate)
    {
        static_eval = Evaluator::evaluate(fb, hm);
        td.static_eval_stack[ply] = static_eval;
        if (ply >= 2 && td.static_eval_stack[ply - 2] != ThreadData::NO_EVAL)
            improving = static_eval > td.static_eval_stack[ply - 2];
    }
    else
        td.static_eval_stack[ply] = ThreadData::NO_EVAL;

    // Null-move pruning
    constexpr int NMP_R = 3;
    if (allow_null && !in_check && !near_mate && depth >= NMP_R + 1 &&
        ((fb.turn == 1 && wp >= 2) || (fb.turn == -1 && bp >= 2)))
    {
        fb.turn = -fb.turn;
        fb.zhash ^= zobrist.turn;
        int nv = -negamax(fb, depth - NMP_R - 1, -beta, -beta + 1, ply + 1, false, wp, bp, extensions, hm, td);
        fb.turn = -fb.turn;
        fb.zhash ^= zobrist.turn;
        if (nv >= beta)
            return nv;
    }

    // Reverse futility pruning
    static const int RFP_BASE[4] = {0, 100, 200, 300};
    if (static_eval && depth >= 1 && depth <= 3)
    {
        int m = RFP_BASE[depth] * (improving ? 1 : 2);
        if (static_eval - m >= beta)
            return static_eval;
    }

    // Futility pruning
    static const int FUT_BASE[4] = {0, 150, 350, 600};
    if (static_eval && depth >= 1 && depth <= 3)
    {
        int m = FUT_BASE[depth] * (improving ? 1 : 2);
        if (static_eval + m <= alpha)
            return quiescence(fb, alpha, beta, ply, hm, td);
    }

    int lmp_base = 4 + depth * depth;
    int lmp_limit = improving ? lmp_base : lmp_base / 2;

    uint32_t countermove = 0;
    if (!fb.history.empty())
    {
        const auto &he = fb.history.back();
        countermove = td.countermoves[std::abs(he.piece)][he.to_sq];
    }

    auto pseudo = MoveGenerator::generate_pseudo_moves(fb);
    auto moves = order_moves(fb, pseudo, std::min(ply, 63), tt_move, countermove, td);

    int best = -MATE_SCORE, alpha_orig = alpha;
    uint32_t best_move = 0, legal_count = 0;
    uint32_t searched_quiets[128];
    int sqc = 0;

    for (size_t i = 0; i < moves.size(); ++i)
    {
        if ((td.nodes & 15) == 0 && std::chrono::steady_clock::now() > deadline)
        {
            timed_out.store(true, std::memory_order_relaxed);
            return best;
        }

        uint32_t move = moves[i];
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        if (std::abs(cap) == 2)
            continue;

        int8_t piece = fb.grid[FastBoard::sq(fr, fc)];
        bool is_cap = (cap != 0);
        bool is_promo = (std::abs(piece) == 7 && ((piece > 0 && tr == 6) || (piece < 0 && tr == 0)));
        bool is_dk = (std::abs(piece) == 7);

        fb.make_move(move, zobrist);
        shared_tt.prefetch(fb.zhash); // prefetch child's bucket while we finish this node
        if (fb.is_in_check(-fb.turn))
        {
            fb.unmake_move();
            continue;
        }
        ++legal_count;

        int nwp = wp, nbp = bp;
        if (is_cap && std::abs(cap) != 2 && std::abs(cap) != 7)
        {
            if (cap > 0)
                --nwp;
            else
                --nbp;
        }
        if (is_promo)
        {
            if (piece > 0)
                ++nwp;
            else
                ++nbp;
        }

        int chm = (is_cap || is_promo || is_dk) ? 0 : hm + 1;

        // LMP
        if (!is_cap && !is_promo && !in_check && !near_mate &&
            static_cast<int>(i) >= lmp_limit)
        {
            fb.unmake_move();
            continue;
        }

        if (!is_cap)
            searched_quiets[sqc++] = move;

        bool gives_check = fb.is_in_check(fb.turn);
        int cext = extensions, cadd = 0;
        if (gives_check && cext < MAX_EXTENSIONS)
        {
            cadd = 1;
            ++cext;
        }
        int cdepth = depth - 1 + cadd;

        // LMR
        int reduction = 0;
        if (i >= 3 && cdepth >= 3 && !is_cap && !is_promo &&
            !in_check && !gives_check && !near_mate)
        {
            reduction = 1;
            if (i >= 6)
                ++reduction;
            if (cdepth >= 6)
                ++reduction;
            reduction = std::min(reduction, cdepth - 1);
        }

        int val;
        if (i == 0)
            val = -negamax(fb, cdepth, -beta, -alpha, ply + 1, true, nwp, nbp, cext, chm, td);
        else
        {
            val = -negamax(fb, cdepth - reduction, -alpha - 1, -alpha, ply + 1, true, nwp, nbp, cext, chm, td);
            if (val > alpha && (reduction > 0 || val < beta))
                val = -negamax(fb, cdepth, -beta, -alpha, ply + 1, true, nwp, nbp, cext, chm, td);
        }

        fb.unmake_move();

        if (val > best)
        {
            best = val;
            best_move = move;
        }
        if (val > alpha)
            alpha = val;
        if (alpha >= beta)
        {
            if (!is_cap)
            {
                int pc = std::min(ply, 63);
                if (td.killers[pc][0] != move)
                {
                    td.killers[pc][1] = td.killers[pc][0];
                    td.killers[pc][0] = move;
                }
                int bonus = depth * depth;
                td.history[fr][fc][tr][tc] += bonus;
                if (!fb.history.empty())
                {
                    const auto &he = fb.history.back();
                    int ppt = std::abs(he.piece), pto = he.to_sq;
                    td.countermoves[ppt][pto] = move;
                    int16_t &ch = td.cont_history[ppt][pto]
                                                 [FastBoard::sq(fr, fc)][FastBoard::sq(tr, tc)];
                    ch = static_cast<int16_t>(std::max<int>(-8192, std::min<int>(8192, ch + bonus)));
                }
                for (int j = 0; j < sqc; ++j)
                {
                    if (searched_quiets[j] == move)
                        continue;
                    int pr, pc2, qr, qc, ca;
                    MoveGenerator::unpack_move(searched_quiets[j], pr, pc2, qr, qc, ca);
                    td.history[pr][pc2][qr][qc] = std::max(0, td.history[pr][pc2][qr][qc] - bonus / 4);
                    if (!fb.history.empty())
                    {
                        const auto &he = fb.history.back();
                        int ppt = std::abs(he.piece), pto = he.to_sq;
                        int16_t &ch = td.cont_history[ppt][pto]
                                                     [FastBoard::sq(pr, pc2)][FastBoard::sq(qr, qc)];
                        ch = static_cast<int16_t>(std::max<int>(-8192, std::min<int>(8192, ch - bonus / 4)));
                    }
                }
            }
            break;
        }
    }

    // No legal moves = loss (NO stalemate in Duel of the Seven Crowns)
    if (legal_count == 0)
        return -MATE_SCORE + ply;

    TTFlag flag = (best <= alpha_orig) ? TT_UPPER : (best >= beta) ? TT_LOWER
                                                                   : TT_EXACT;
    shared_tt.store(key, depth, flag, best, best_move, static_cast<uint8_t>(tt_age), ply);

    return best;
}

// ─── SMP worker ────────────────────────────────────────────────
// Each helper thread runs genuine independent iterative deepening with:
//
//  1. DEPTH SKIPPING  — thread i skips depth d when d % skip_mod != 0,
//     where skip_mod cycles through {1,2,3} across threads.  This spreads
//     workers across different depth levels instead of stampeding the same
//     depth simultaneously, and populates the TT at multiple granularities.
//
//  2. ROOT MOVE ROTATION — the root move list is rotated by thread_id so
//     each helper explores the tree from a different first move.  Moves
//     that the main thread evaluates last, helpers evaluate first, filling
//     TT entries the main thread will then benefit from.
//
//  3. INDEPENDENT ASPIRATION — each helper maintains its own best score
//     and aspiration window rather than sharing the main thread's, so
//     their windows open independently and avoid a herding effect.
//
// FastBoard is taken BY VALUE (intentionally): each thread owns its own
// copy of the position with its own undo-history stack.  The caller passes
// a copy constructed from the original, so the main-thread board is safe.

void Searcher::smp_worker(FastBoard board, // by value — thread owns its copy
                          int thread_id,
                          int max_depth,
                          int halfmove_clock,
                          int wp, int bp,
                          std::vector<uint32_t> root_moves)
{
    ThreadData td;
    td.id = thread_id;
    td.clear();

    // Depth-skip modulus: cycle {1,2,3} across threads so some skip odd depths,
    // some skip every 3rd depth, and some search every depth.
    // thread 1 -> skip_mod 2 (skip even depths)
    // thread 2 -> skip_mod 3
    // thread 3 -> skip_mod 2
    // thread 4 -> skip_mod 3 ... etc.
    // thread_id 0 is the main thread and never calls this function.
    static const int SKIP_MODS[] = {1, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3};
    int skip_mod = SKIP_MODS[std::min(thread_id, 14)];

    int best_score = 0;
    int asp_window = 50;

    for (int d = 1; d <= max_depth; ++d)
    {
        if (timed_out.load(std::memory_order_relaxed))
            break;

        // Depth skipping: thread skips depths that don't align to its modulus
        if (skip_mod > 1 && (d % skip_mod) != (thread_id % skip_mod))
            continue;

        int lo = best_score - asp_window;
        int hi = best_score + asp_window;
        if (std::abs(best_score) >= NEAR_MATE || d <= 2)
        {
            lo = -MATE_SCORE;
            hi = MATE_SCORE;
        }

        // Search the rotated root move list at depth d
        // We drive a miniature root loop here so the helper contributes
        // independently discovered TT entries at each depth.
        int depth_best = -MATE_SCORE;
        for (size_t i = 0; i < root_moves.size(); ++i)
        {
            if (timed_out.load(std::memory_order_relaxed))
                goto worker_done;
            uint32_t move = root_moves[i];

            int fr, fc, tr, tc, cap;
            MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
            if (std::abs(cap) == 2)
                continue;

            board.make_move(move, zobrist);
            if (board.is_in_check(-board.turn))
            {
                board.unmake_move();
                continue;
            }

            int nwp = wp, nbp = bp;
            if (cap && std::abs(cap) != 2 && std::abs(cap) != 7)
            {
                if (cap > 0)
                    --nwp;
                else
                    --nbp;
            }

            int8_t piece = board.history.back().piece;
            bool is_promo = (std::abs(piece) == 7 && ((piece > 0 && tr == 6) || (piece < 0 && tr == 0)));
            bool is_dk = (std::abs(piece) == 7);
            int chm = (cap || is_promo || is_dk) ? 0 : halfmove_clock + 1;

            int val;
            if (i == 0)
                val = -negamax(board, d - 1, -hi, -lo, 1, true, nwp, nbp, 0, chm, td);
            else
            {
                val = -negamax(board, d - 1, -lo - 1, -lo, 1, true, nwp, nbp, 0, chm, td);
                if (val > lo && val < hi)
                    val = -negamax(board, d - 1, -hi, -lo, 1, true, nwp, nbp, 0, chm, td);
            }
            board.unmake_move();

            if (val > depth_best)
                depth_best = val;
            if (val > lo)
                lo = val;
            if (lo >= hi)
                break; // beta cutoff at root
        }

        if (!timed_out.load(std::memory_order_relaxed) && depth_best > -MATE_SCORE)
        {
            best_score = depth_best;
            asp_window = std::max(25, std::abs(best_score) / 8 + 25);
        }
    }

worker_done:
    atomic_total_nodes.fetch_add(td.nodes, std::memory_order_relaxed);
}

// ─── find_best_move ────────────────────────────────────────────
Searcher::SearchResult Searcher::find_best_move(const FastBoard &fb, int max_depth,
                                                double time_limit_sec, int halfmove_clock, int num_threads)
{
    SearchResult result;
    tt_age = (tt_age + 1) & 0xFF;
    timed_out.store(false, std::memory_order_relaxed);
    atomic_total_nodes.store(0, std::memory_order_relaxed);

    auto start_time = std::chrono::steady_clock::now();
    deadline = start_time + std::chrono::milliseconds(
                                static_cast<int64_t>(time_limit_sec * 1000));

    FastBoard board(fb);
    auto legal = MoveGenerator::generate_legal_moves(board);
    if (legal.empty())
    {
        result.mate_info = "";
        return result;
    }

    // Count non-king, non-donkey pieces for null-move guard
    int wp = 0, bp = 0;
    for (int i = 0; i < TOTAL_SQUARES; ++i)
    {
        int p = board.grid[i];
        if (!p)
            continue;
        int pt = std::abs(p);
        if (pt != 2 && pt != 7)
        {
            if (p > 0)
                ++wp;
            else
                ++bp;
        }
    }

    // Seed root order from TT
    {
        uint32_t ttm = 0;
        int tts = 0;
        TTFlag ttf = TT_NONE;
        shared_tt.probe(board.zhash ^ zobrist.hm_key(halfmove_clock), 1, -MATE_SCORE, MATE_SCORE, 0, ttm, tts, ttf);
        if (ttm)
        {
            auto it = std::find(legal.begin(), legal.end(), ttm);
            if (it != legal.end())
                std::swap(legal[0], *it);
        }
    }

    // Prepare rotated root-move lists for each helper thread.
    // Thread i starts from legal[i % legal.size()] and wraps around.
    int actual_helpers = std::max(0, num_threads - 1);
    std::vector<std::vector<uint32_t>> helper_roots(actual_helpers);
    for (int tid = 1; tid <= actual_helpers; ++tid)
    {
        auto &rm = helper_roots[tid - 1];
        rm.reserve(legal.size());
        int offset = tid % static_cast<int>(legal.size());
        for (int j = 0; j < static_cast<int>(legal.size()); ++j)
            rm.push_back(legal[(offset + j) % legal.size()]);
    }

    // Launch helper threads — each gets its OWN FastBoard copy
    std::vector<std::thread> helpers;
    helpers.reserve(actual_helpers);
    for (int tid = 1; tid <= actual_helpers; ++tid)
    {
        // FastBoard(fb) constructs a copy; the thread takes it by value (moved in)
        helpers.emplace_back([this, tid, max_depth, halfmove_clock, wp, bp,
                              board_copy = FastBoard(fb),
                              root_moves = helper_roots[tid - 1]]() mutable
                             { smp_worker(std::move(board_copy), tid, max_depth,
                                          halfmove_clock, wp, bp, std::move(root_moves)); });
    }

    // ── Main thread: iterative deepening with aspiration windows ──
    ThreadData main_td;
    main_td.id = 0;
    main_td.clear();

    uint32_t best_move_so_far = legal[0];
    int best_score_so_far = 0;
    int asp_window = 50;

    try
    {
        for (int d = 1; d <= max_depth; ++d)
        {
            auto now = std::chrono::steady_clock::now();
            if (std::chrono::duration<double>(deadline - now).count() < time_limit_sec * 0.05)
                break;

            int lo, hi;
            if (std::abs(best_score_so_far) >= NEAR_MATE || d <= 2)
            {
                lo = -MATE_SCORE;
                hi = MATE_SCORE;
            }
            else
            {
                int w = std::max(asp_window, std::abs(best_score_so_far) / 8 + 50);
                lo = best_score_so_far - w;
                hi = best_score_so_far + w;
            }

            int val = negamax(board, d, lo, hi, 0, false, wp, bp, 0, halfmove_clock, main_td);

            // Aspiration re-search on fail-high or fail-low
            if (!timed_out.load(std::memory_order_relaxed) && (val <= lo || val >= hi))
                val = negamax(board, d, -MATE_SCORE, MATE_SCORE, 0, false, wp, bp, 0, halfmove_clock, main_td);

            if (!timed_out.load(std::memory_order_relaxed))
            {
                best_score_so_far = val;
                result.depth_reached = d;
                asp_window = std::max(25, std::abs(val) / 8 + 25);

                // Pull best move from TT (most reliable source after search)
                uint32_t ttm = 0;
                int tts = 0;
                TTFlag ttf = TT_NONE;
                shared_tt.probe(board.zhash ^ zobrist.hm_key(halfmove_clock), d, lo, hi, 0, ttm, tts, ttf);
                if (ttm)
                {
                    auto it = std::find(legal.begin(), legal.end(), ttm);
                    if (it != legal.end())
                        best_move_so_far = ttm;
                }

                atomic_best_move.store(best_move_so_far, std::memory_order_relaxed);
                atomic_best_score.store(best_score_so_far, std::memory_order_relaxed);

                if (std::abs(best_score_so_far) >= NEAR_MATE)
                    break;
            }
        }
    }
    catch (...)
    {
    }

    // Stop all helpers and collect node counts
    timed_out.store(true, std::memory_order_relaxed);
    for (auto &t : helpers)
        if (t.joinable())
            t.join();

    auto end_time = std::chrono::steady_clock::now();
    result.time_ms = std::chrono::duration<double, std::milli>(end_time - start_time).count();
    result.nodes_searched = atomic_total_nodes.load(std::memory_order_relaxed) + main_td.nodes;
    result.best_move = atomic_best_move.load(std::memory_order_relaxed);
    result.score = atomic_best_score.load(std::memory_order_relaxed);

    bool is_white = (fb.turn == 1);
    result.mate_info = format_mate(is_white ? result.score : -result.score);
    return result;
}

int Searcher::evaluate_board(const FastBoard &fb, int halfmove_clock)
{
    if (fb.is_insufficient_material() || halfmove_clock >= 40)
        return 0;
    return Evaluator::evaluate(fb, halfmove_clock);
}

// ═══════════════════════════════════════════════════════════════
// Perft
// ═══════════════════════════════════════════════════════════════
static uint64_t perft_count(FastBoard &fb, int depth, const ZobristKeys &zobrist)
{
    if (depth == 0)
        return 1;
    auto moves = MoveGenerator::generate_legal_moves(fb);
    if (depth == 1)
        return moves.size();
    uint64_t nodes = 0;
    for (uint32_t move : moves)
    {
        fb.make_move(move, zobrist);
        nodes += perft_count(fb, depth - 1, zobrist);
        fb.unmake_move();
    }
    return nodes;
}

static String square_name(int r, int c)
{
    static const char *f = "abcdefg", *k = "7654321";
    return String::chr(f[c]) + String::chr(k[r]);
}

// ═══════════════════════════════════════════════════════════════
// Godot Wrapper
// ═══════════════════════════════════════════════════════════════
DuelEngine::DuelEngine() : searcher(std::make_unique<Searcher>()) {}

void DuelEngine::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("set_board", "board_array", "turn"), &DuelEngine::set_board);
    ClassDB::bind_method(D_METHOD("find_best_move", "max_depth", "time_limit", "halfmove_clock", "num_threads"), &DuelEngine::find_best_move, DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("get_recommended_threads"), &DuelEngine::get_recommended_threads);
    ClassDB::bind_method(D_METHOD("evaluate_position", "halfmove_clock"), &DuelEngine::evaluate_position);
    ClassDB::bind_method(D_METHOD("get_legal_moves", "row", "col"), &DuelEngine::get_legal_moves);
    ClassDB::bind_method(D_METHOD("get_piece_moves", "row", "col"), &DuelEngine::get_piece_moves);
    ClassDB::bind_method(D_METHOD("get_piece_attack_squares", "row", "col"), &DuelEngine::get_piece_attack_squares);
    ClassDB::bind_method(D_METHOD("is_checkmate"), &DuelEngine::is_checkmate);
    ClassDB::bind_method(D_METHOD("is_in_check", "color"), &DuelEngine::is_in_check);
    ClassDB::bind_method(D_METHOD("is_insufficient_material"), &DuelEngine::is_insufficient_material);
    ClassDB::bind_method(D_METHOD("make_move", "from_r", "from_c", "to_r", "to_c"), &DuelEngine::make_move);
    ClassDB::bind_method(D_METHOD("undo_move"), &DuelEngine::undo_move);
    ClassDB::bind_method(D_METHOD("clear_tables"), &DuelEngine::clear_tables);
    ClassDB::bind_method(D_METHOD("get_engine_info"), &DuelEngine::get_engine_info);
    ClassDB::bind_method(D_METHOD("perft", "depth"), &DuelEngine::perft);
    ClassDB::bind_method(D_METHOD("perft_divide", "depth"), &DuelEngine::perft_divide);
}

void DuelEngine::set_board(const Array &board_array, const String &turn)
{
    if (board_array.size() != BOARD_SIZE)
    {
        UtilityFunctions::push_error("set_board: expected 7 rows");
        return;
    }

    board.grid.fill(0);
    board.turn = (turn == "white") ? 1 : -1;
    board.history.clear();
    board.zhash = 0;
    board.wking_sq = -1;
    board.bking_sq = -1;

    for (int r = 0; r < BOARD_SIZE; ++r)
    {
        if (board_array[r].get_type() != Variant::ARRAY)
        {
            UtilityFunctions::push_error("set_board: row not array");
            continue;
        }
        Array row = board_array[r];
        if (row.size() != BOARD_SIZE)
        {
            UtilityFunctions::push_error("set_board: expected 7 cols");
            continue;
        }
        for (int c = 0; c < BOARD_SIZE; ++c)
        {
            String cell = row[c];
            if (cell == "")
            {
                board.grid[FastBoard::sq(r, c)] = 0;
                continue;
            }
            bool iw = (cell[0] == 'w');
            char pt = static_cast<char>(cell.unicode_at(1));
            int code = 0;
            switch (pt)
            {
            case 'K':
                code = 2;
                break;
            case 'N':
                code = 3;
                break;
            case 'C':
                code = 4;
                break;
            case 'P':
                code = 5;
                break;
            case 'M':
                code = 6;
                break;
            case 'D':
                code = 7;
                break;
            case 'L':
                code = 8;
                break;
            case 'W':
                code = 9;
                break;
            }
            board.grid[FastBoard::sq(r, c)] = iw ? code : -code;
            if (code == 2 && iw)
                board.wking_sq = FastBoard::sq(r, c);
            if (code == 2 && !iw)
                board.bking_sq = FastBoard::sq(r, c);
        }
    }

    board.zhash = 0;
    for (int r = 0; r < BOARD_SIZE; ++r)
        for (int c = 0; c < BOARD_SIZE; ++c)
        {
            int p = board.grid[FastBoard::sq(r, c)];
            if (p)
                board.zhash ^= searcher->zobrist.piece_square[p + 9][r][c];
        }
    if (board.turn == -1)
        board.zhash ^= searcher->zobrist.turn;
}

Dictionary DuelEngine::find_best_move(int max_depth, double time_limit, int halfmove_clock, int num_threads)
{
    Dictionary result;

    // -1 (the default) means "caller didn't specify" -> use the machine's
    // recommended count. A caller-supplied value is still clamped to
    // [1, DEFAULT_SMP_THREADS] so a bad value from GDScript (0, negative,
    // or something absurd) can't oversubscribe the machine or index past
    // smp_worker's SKIP_MODS[] array.
    int threads = (num_threads <= 0) ? recommended_thread_count()
                                     : std::clamp(num_threads, 1, DEFAULT_SMP_THREADS);

    auto sr = searcher->find_best_move(board, max_depth, time_limit, halfmove_clock, threads);
    if (sr.best_move != 0)
    {
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(sr.best_move, fr, fc, tr, tc, cap);
        result["from_row"] = fr;
        result["from_col"] = fc;
        result["to_row"] = tr;
        result["to_col"] = tc;
        result["score"] = sr.score;
        result["mate"] = sr.mate_info;
        result["depth"] = sr.depth_reached;
        result["nodes"] = sr.nodes_searched;
        result["time_ms"] = sr.time_ms;
    }
    else
        result["error"] = "No legal moves";
    return result;
}

int DuelEngine::get_recommended_threads()
{
    return recommended_thread_count();
}

float DuelEngine::evaluate_position(int halfmove_clock)
{
    int score = searcher->evaluate_board(board, halfmove_clock);
    if (board.turn == -1)
        score = -score;
    return static_cast<float>(score);
}

Array DuelEngine::get_legal_moves(int row, int col)
{
    Array moves;
    if (row < 0 || row >= BOARD_SIZE || col < 0 || col >= BOARD_SIZE)
        return moves;
    int p = board.grid[FastBoard::sq(row, col)];
    if (!p || (p > 0) != (board.turn > 0))
        return moves;
    auto legal = MoveGenerator::generate_legal_moves(board);
    for (uint32_t move : legal)
    {
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        if (fr == row && fc == col)
        {
            Dictionary m;
            m["to_row"] = tr;
            m["to_col"] = tc;
            m["capture"] = (cap != 0);
            moves.append(m);
        }
    }
    return moves;
}

Array DuelEngine::get_piece_moves(int row, int col)
{
    Array moves;
    if (row < 0 || row >= BOARD_SIZE || col < 0 || col >= BOARD_SIZE)
        return moves;
    auto pseudo = MoveGenerator::generate_piece_pseudo_moves(board, row, col);
    for (uint32_t move : pseudo)
    {
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        Dictionary m;
        m["to_row"] = tr;
        m["to_col"] = tc;
        m["capture"] = (cap != 0);
        moves.append(m);
    }
    return moves;
}

Array DuelEngine::get_piece_attack_squares(int row, int col)
{
    Array moves;
    if (row < 0 || row >= BOARD_SIZE || col < 0 || col >= BOARD_SIZE)
        return moves;
    auto pseudo = MoveGenerator::generate_piece_attack_squares(board, row, col);
    int8_t mover = board.grid[FastBoard::sq(row, col)];
    for (uint32_t move : pseudo)
    {
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        int8_t target = board.grid[FastBoard::sq(tr, tc)];
        Dictionary m;
        m["to_row"] = tr;
        m["to_col"] = tc;
        m["capture"] = (target != 0);
        m["is_friendly"] = (target != 0 && (target > 0) == (mover > 0));
        moves.append(m);
    }
    return moves;
}

bool DuelEngine::is_checkmate()
{
    return MoveGenerator::generate_legal_moves(board).empty();
}

bool DuelEngine::is_in_check(const String &color)
{
    return board.is_in_check((color == "white") ? 1 : -1);
}

bool DuelEngine::is_insufficient_material()
{
    return board.is_insufficient_material();
}

bool DuelEngine::make_move(int from_r, int from_c, int to_r, int to_c)
{
    if (from_r < 0 || from_r >= BOARD_SIZE || from_c < 0 || from_c >= BOARD_SIZE ||
        to_r < 0 || to_r >= BOARD_SIZE || to_c < 0 || to_c >= BOARD_SIZE)
        return false;
    auto legal = MoveGenerator::generate_legal_moves(board);
    for (uint32_t move : legal)
    {
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        if (fr == from_r && fc == from_c && tr == to_r && tc == to_c)
        {
            board.make_move(move, searcher->zobrist);
            return true;
        }
    }
    return false;
}

void DuelEngine::undo_move() { board.unmake_move(); }
void DuelEngine::clear_tables() { searcher->clear_tables(); }

String DuelEngine::get_engine_info()
{
    return "Duel of the Seven Crowns Engine v2.2\n"
           "C++ GDExtension for Godot 4.x\n"
           "Fixes: lockless XOR-checksum TT (was unsynchronized across "
           "DEFAULT_SMP_THREADS, causing torn writes / corrupted mate scores), "
           "int32_t TT value (was int16_t — mate score overflow), "
           "genuine Lazy SMP w/ depth-skip + root rotation\n"
           "Features: Lazy SMP (auto-scaled threads, up to 15), 4-way bucketed TT (64MB) + prefetch, "
           "MVV-LVA, butterfly history + gravity, IID, aspiration, SEE, "
           "countermoves, continuation history, "
           "passed-donkey eval, outpost bonus, king-structure eval";
}

int64_t DuelEngine::perft(int depth)
{
    if (depth <= 0)
        return 1;
    return static_cast<int64_t>(perft_count(board, depth, searcher->zobrist));
}

Dictionary DuelEngine::perft_divide(int depth)
{
    Dictionary result;
    if (depth <= 0)
        return result;
    auto moves = MoveGenerator::generate_legal_moves(board);
    for (uint32_t move : moves)
    {
        int fr, fc, tr, tc, cap;
        MoveGenerator::unpack_move(move, fr, fc, tr, tc, cap);
        board.make_move(move, searcher->zobrist);
        uint64_t cnt = perft_count(board, depth - 1, searcher->zobrist);
        board.unmake_move();
        result[square_name(fr, fc) + square_name(tr, tc)] = static_cast<int64_t>(cnt);
    }
    return result;
}