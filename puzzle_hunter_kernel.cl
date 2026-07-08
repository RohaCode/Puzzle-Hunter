#ifndef _PUZZLE_HUNTER_KERNEL_CL
#define _PUZZLE_HUNTER_KERNEL_CL

#ifndef MAX_BYTE_COUNT
#define MAX_BYTE_COUNT 32
#endif

#include "secp256k1.cl"
#include "hash160.cl"

typedef struct {
    uint256_t x;
    uint256_t y;
} point_affine_t;

typedef struct {
    uint256_t x;
    uint256_t y;
    uint256_t z;
} point_projective_t;

typedef struct {
    unsigned int flag;
    uint256_t privKey;
    uint256_t x;
    uint256_t y;
    uchar hash160[20];
} puzzle_hunter_result_t;

typedef struct {
    ulong s0;
    ulong s1;
    ulong s2;
    ulong s3;
} xoshiro_state_t;

static inline ulong rotl64(ulong x, int k)
{
    return (x << k) | (x >> (64 - k));
}

static inline ulong xoshiro_next(xoshiro_state_t* state)
{
    const ulong result = rotl64(state->s1 * 5, 7) * 9; // xoshiro256**
    const ulong t = state->s1 << 17;

    state->s2 ^= state->s0;
    state->s3 ^= state->s1;
    state->s1 ^= state->s2;
    state->s0 ^= state->s3;

    state->s2 ^= t;
    state->s3 = rotl64(state->s3, 45);

    return result;
}

static inline unsigned int getKeyByte(uint256_t key, int byteIndex)
{
    return (key.v[7 - (byteIndex / 4)] >> ((byteIndex & 3) * 8)) & 0xff;
}

static inline point_projective_t addMixedPH(point_projective_t p1, point_affine_t p2)
{
    uint256_t u1 = mulModP256k(p2.y, p1.z);
    uint256_t v1 = mulModP256k(p2.x, p1.z);
    uint256_t u = subModP256k(u1, p1.y);
    uint256_t v = subModP256k(v1, p1.x);
    uint256_t us2 = squareModP256k(u);
    uint256_t vs2 = squareModP256k(v);
    uint256_t vs3 = mulModP256k(vs2, v);
    uint256_t us2w = mulModP256k(us2, p1.z);
    uint256_t vs2v2 = mulModP256k(vs2, p1.x);
    uint256_t twoVs2v2 = addModP256k(vs2v2, vs2v2);
    uint256_t a = subModP256k(us2w, vs3);
    a = subModP256k(a, twoVs2v2);

    point_projective_t r;
    r.x = mulModP256k(v, a);
    uint256_t vs3u2 = mulModP256k(vs3, p1.y);
    r.y = subModP256k(vs2v2, a);
    r.y = mulModP256k(r.y, u);
    r.y = subModP256k(r.y, vs3u2);
    r.z = mulModP256k(vs3, p1.z);
    return r;
}

static inline bool computePublicKeyProjectivePH(uint256_t privKey, __global const point_affine_t* gTable, point_projective_t* outQ)
{
    int i = 0;
    unsigned int b = 0;

    for(i = 0; i < MAX_BYTE_COUNT; i++) {
        b = getKeyByte(privKey, i);
        if(b != 0) break;
    }

    if(i >= MAX_BYTE_COUNT) return false;

    point_projective_t q;
    q.x = gTable[i * 256 + (int)b - 1].x;
    q.y = gTable[i * 256 + (int)b - 1].y;
    q.z = (uint256_t){{0, 0, 0, 0, 0, 0, 0, 1}};

    for(i = i + 1; i < MAX_BYTE_COUNT; i++) {
        b = getKeyByte(privKey, i);
        if(b != 0) {
            q = addMixedPH(q, gTable[i * 256 + (int)b - 1]);
        }
    }

    *outQ = q;
    return true;
}

static inline uint256_t one256()
{
    return (uint256_t){{0, 0, 0, 0, 0, 0, 0, 1}};
}

static inline uint256_t zero256()
{
    return (uint256_t){{0, 0, 0, 0, 0, 0, 0, 0}};
}

static inline uint256_t negModP256k(uint256_t a)
{
    if(equal256k(a, zero256())) return a;
    return subModP256k(zero256(), a);
}

static inline bool toAffinePH(point_projective_t* q, point_affine_t* aff) {
    if(equal256k(q->z, zero256())) return false;
    uint256_t invZ = invModP256k(q->z);
    aff->x = mulModP256k(q->x, invZ);
    aff->y = mulModP256k(q->y, invZ);
    return true;
}

static inline uint256_t add256Raw(uint256_t a, uint256_t b)
{
    unsigned int carry = 0;
    for(int i = 7; i >= 0; i--) {
        a.v[i] = addc(a.v[i], b.v[i], &carry);
    }
    return a;
}

static inline uint256_t generateRandomKeyInRange(xoshiro_state_t* state, uint256_t minKey, uint256_t mask, uint256_t limit)
{
    uint256_t value;
    int retries = 0;
    do {
        #if MAX_BYTE_COUNT <= 8
        ulong r = xoshiro_next(state);
        value.v[6] = (unsigned int)(r >> 32);
        value.v[7] = (unsigned int)r;
        value.v[0] = 0; value.v[1] = 0; value.v[2] = 0; value.v[3] = 0; value.v[4] = 0; value.v[5] = 0;
        #elif MAX_BYTE_COUNT <= 16
        ulong r0 = xoshiro_next(state);
        value.v[6] = (unsigned int)(r0 >> 32);
        value.v[7] = (unsigned int)r0;
        ulong r1 = xoshiro_next(state);
        value.v[4] = (unsigned int)(r1 >> 32);
        value.v[5] = (unsigned int)r1;
        value.v[0] = 0; value.v[1] = 0; value.v[2] = 0; value.v[3] = 0;
        #elif MAX_BYTE_COUNT <= 24
        ulong r0 = xoshiro_next(state);
        value.v[6] = (unsigned int)(r0 >> 32);
        value.v[7] = (unsigned int)r0;
        ulong r1 = xoshiro_next(state);
        value.v[4] = (unsigned int)(r1 >> 32);
        value.v[5] = (unsigned int)r1;
        ulong r2 = xoshiro_next(state);
        value.v[2] = (unsigned int)(r2 >> 32);
        value.v[3] = (unsigned int)r2;
        value.v[0] = 0; value.v[1] = 0;
        #else
        for(int i = 0; i < 4; i++) {
            ulong r = xoshiro_next(state);
            value.v[i * 2] = (unsigned int)(r >> 32);
            value.v[i * 2 + 1] = (unsigned int)r;
        }
        #endif

        // Apply mask to random part
        for(int i = 0; i < 8; i++) value.v[i] &= mask.v[i];
        retries++;
    } while (!isGreaterOrEqual256(limit, value) && retries < 16);

    return add256Raw(minKey, value);
}

static inline void copyHash160ToResult(const uchar hash[20], __global puzzle_hunter_result_t* result)
{
    for(int i = 0; i < 20; i++) {
        result->hash160[i] = hash[i];
    }
}

static inline void storeMatchResult(uint256_t privKey, uint256_t x, uint256_t y, const uchar hash[20],
                                    __constant const uchar* targetHash160, __global puzzle_hunter_result_t* result)
{
    if(hash160FullMatches(hash, targetHash160)) {
        while (true) {
            unsigned int old = result->flag;
            if (old == 2u || old == 4u) {
                // Full match is already complete or currently writing
                break;
            }
            if (old == 3u) {
                // Partial match is currently writing. Spin-wait.
                continue;
            }
            // old is 0 or 1. Try to transition to 4 (full match writing lock)
            if (atomic_cmpxchg((volatile __global unsigned int*)&result->flag, old, 4u) == old) {
                result->privKey = privKey;
                result->x = x;
                result->y = y;
                copyHash160ToResult(hash, result);
                atomic_xchg((volatile __global unsigned int*)&result->flag, 2u); // Mark full match complete
                break;
            }
        }
    } else {
        // Try to transition 0 to 3 (partial match writing lock)
        if(atomic_cmpxchg((volatile __global unsigned int*)&result->flag, 0u, 3u) == 0u) {
            result->privKey = privKey;
            result->x = x;
            result->y = y;
            copyHash160ToResult(hash, result);
            atomic_xchg((volatile __global unsigned int*)&result->flag, 1u); // Mark partial match complete
        }
    }
}

static inline uint256_t addSmall256(uint256_t a, unsigned int value)
{
    unsigned int carry = value;
    for(int i = 7; i >= 0; i--) {
        unsigned int old = a.v[i];
        a.v[i] += carry;
        carry = (carry != 0 && a.v[i] < old) ? 1 : 0;
    }
    return a;
}

static inline uint256_t subSmall256(uint256_t a, unsigned int value)
{
    unsigned int borrow = value;
    for(int i = 7; i >= 0; i--) {
        unsigned int old = a.v[i];
        a.v[i] -= borrow;
        borrow = (borrow != 0 && old < borrow) ? 1 : 0;
    }
    return a;
}

__kernel void puzzle_hunter_search_gpu(
    __global xoshiro_state_t* rngStates,
    __global const point_affine_t* gTable,
    __constant const uchar* targetHash160,
    const int prefixLen,
    __global point_affine_t* startPoints,
    __global puzzle_hunter_result_t* result,
    __global uint256_t* baseKeys,
    const uint256_t minKey,
    const uint256_t rangeMask,
    const uint256_t rangeLimit)
{
    const int gid = get_global_id(0);
    
    // 1. Read state from global memory
    xoshiro_state_t state = rngStates[gid];
    
    // 2. Protection against "death state" (all zeros)
    if (state.s0 == 0 && state.s1 == 0 && state.s2 == 0 && state.s3 == 0) {
        state.s0 = 0x9E3779B97F4A7C15UL ^ (ulong)gid;
        state.s1 = 0xBF58476D1CE4E5B9UL;
        state.s2 = 0x94D049BB133111EBUL;
        state.s3 = 0x123456789ABCDEF0UL;
    }

    // 3. Generate random key (modifies state locally)
    uint256_t baseKey = generateRandomKeyInRange(&state, minKey, rangeMask, rangeLimit);
    
    // 4. IMPORTANT: Write updated state back to global memory
    rngStates[gid] = state;
    
    baseKeys[gid] = baseKey;

    point_projective_t q;
    if(!computePublicKeyProjectivePH(baseKey, gTable, &q)) return;

    point_affine_t aff;
    if(!toAffinePH(&q, &aff)) return;

    startPoints[gid] = aff;

    uchar hash[20];
    hash160CompressedBytes(aff.x, aff.y, hash);
    if(hash160PrefixMatches(hash, targetHash160, prefixLen)) {
        storeMatchResult(baseKey, aff.x, aff.y, hash, targetHash160, result);
    }
}

// BATCH_SIZE is now defined via -D at compile time

__kernel void puzzle_hunter_check_batch_thread_gpu(
    __global const uint256_t* baseKeys,
    __global const point_affine_t* batchTable,
    __constant const uchar* targetHash160,
    const int prefixLen,
    __global const point_affine_t* startPoints,
    __global puzzle_hunter_result_t* result,
    __global uint256_t* chain,
    const uint256_t minKey)
{
    const int gid = get_global_id(0);
    const int lid = get_local_id(0);
    const int lsize = get_local_size(0);
    const int dim = get_global_size(0);

    __local uint256_t loc_factors[LOCAL_SIZE];
    __local uint256_t loc_prefixes[LOCAL_SIZE];
    __local uint256_t loc_inverted[LOCAL_SIZE];

    uint256_t startX = startPoints[gid].x;
    uint256_t startY = startPoints[gid].y;
    uint256_t negStartY = negModP256k(startY);

    uint256_t inverse = one256();
    for(int i = 1; i < BATCH_SIZE; i++) {
        point_affine_t offsetPoint = batchTable[i - 1];
        uint256_t denom = subModP256k(offsetPoint.x, startX);
        uint256_t factor = equal256k(denom, zero256()) ? one256() : denom;
        inverse = mulModP256k(inverse, factor);
        chain[(i - 1) * dim + gid] = inverse;
    }

    loc_factors[lid] = inverse;
    barrier(CLK_LOCAL_MEM_FENCE);
    if(lid == 0) {
        uint256_t acc = one256();
        for(int i = 0; i < lsize; i++) {
            loc_prefixes[i] = acc;
            acc = mulModP256k(acc, loc_factors[i]);
        }
        uint256_t invAcc = invModP256k(acc);
        for(int i = lsize - 1; i >= 0; i--) {
            loc_inverted[i] = mulModP256k(invAcc, loc_prefixes[i]);
            invAcc = mulModP256k(invAcc, loc_factors[i]);
        }
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    inverse = loc_inverted[lid];

    if(result->flag == 2) return;

    uint256_t baseKey = baseKeys[gid];

    for(int i = BATCH_SIZE - 1; i >= 1; i--) {
        point_affine_t offsetPoint = batchTable[i - 1];
        uint256_t invDenom;
        uint256_t denom = subModP256k(offsetPoint.x, startX);
        uint256_t factor = equal256k(denom, zero256()) ? one256() : denom;

        if(i > 1) {
            invDenom = mulModP256k(inverse, chain[(i - 2) * dim + gid]);
            inverse = mulModP256k(inverse, factor);
        } else {
            invDenom = inverse;
        }

        uint256_t rise_P = subModP256k(offsetPoint.y, startY);
        uint256_t slope_P = mulModP256k(rise_P, invDenom);
        uint256_t slopeSq_P = squareModP256k(slope_P);
        uint256_t plusX = subModP256k(subModP256k(slopeSq_P, startX), offsetPoint.x);

        uint256_t plusY = addModP256k(negStartY, mulModP256k(slope_P, subModP256k(startX, plusX)));
        uchar plusHash[20];
        hash160CompressedBytes(plusX, plusY, plusHash);
        if(hash160PrefixMatches(plusHash, targetHash160, prefixLen)) {
            uint256_t finalKey = addSmall256(baseKey, (unsigned int)i);
            // Only store if within the original range (no overflow)
            if (isGreaterOrEqual256(finalKey, minKey)) {
                storeMatchResult(finalKey, plusX, plusY, plusHash, targetHash160, result);
            }
        }

        uint256_t rise_M = negModP256k(addModP256k(offsetPoint.y, startY));
        uint256_t slope_M = mulModP256k(rise_M, invDenom);
        uint256_t slopeSq_M = squareModP256k(slope_M);
        uint256_t minusX = subModP256k(subModP256k(slopeSq_M, startX), offsetPoint.x);

        uint256_t minusY = addModP256k(negStartY, mulModP256k(slope_M, subModP256k(startX, minusX)));
        uchar minusHash[20];
        hash160CompressedBytes(minusX, minusY, minusHash);
        if(hash160PrefixMatches(minusHash, targetHash160, prefixLen)) {
            uint256_t finalKey = subSmall256(baseKey, (unsigned int)i);
            // Only store if within the original range
            if (isGreaterOrEqual256(finalKey, minKey)) {
                storeMatchResult(finalKey, minusX, minusY, minusHash, targetHash160, result);
            }
        }
    }
}

#endif
