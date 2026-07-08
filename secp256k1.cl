#ifndef _SECP256K1_CL
#define _SECP256K1_CL

typedef struct {
    unsigned int v[8];
} uint256_t;

// Standard addition with carry (optimized to allow GPU assembly pattern recognition)
static inline unsigned int addc(unsigned int a, unsigned int b, unsigned int* carry)
{
    unsigned int c_in = *carry;
    unsigned int r = a + b + c_in;
    *carry = (r < a) || (r == a && c_in);
    return r;
}

// Standard subtraction with borrow (optimized to allow GPU assembly pattern recognition)
static inline unsigned int subc(unsigned int a, unsigned int b, unsigned int* borrow)
{
    unsigned int b_in = *borrow;
    unsigned int r = a - b - b_in;
    *borrow = (a < b) || (a == b && b_in);
    return r;
}

// Multiply-Add 977 (Specialized for secp256k1 reduction)
static inline void madd977(unsigned int* h, unsigned int* l, unsigned int a, unsigned int b)
{
    unsigned long r = (unsigned long)a * 977 + b;
    *l = (unsigned int)r;
    *h = (unsigned int)(r >> 32);
}

// Check if a == b
static inline bool equal256k(uint256_t a, uint256_t b)
{
    return (a.v[0] == b.v[0]) && (a.v[1] == b.v[1]) && (a.v[2] == b.v[2]) && (a.v[3] == b.v[3]) &&
           (a.v[4] == b.v[4]) && (a.v[5] == b.v[5]) && (a.v[6] == b.v[6]) && (a.v[7] == b.v[7]);
}

// Subtract P = 2^256 - 2^32 - 977
static inline void subP(unsigned int a[8])
{
    unsigned int borrow = 0;
    a[7] = subc(a[7], 0xFFFFFC2F, &borrow);
    a[6] = subc(a[6], 0xFFFFFFFE, &borrow);
    a[5] = subc(a[5], 0xFFFFFFFF, &borrow);
    a[4] = subc(a[4], 0xFFFFFFFF, &borrow);
    a[3] = subc(a[3], 0xFFFFFFFF, &borrow);
    a[2] = subc(a[2], 0xFFFFFFFF, &borrow);
    a[1] = subc(a[1], 0xFFFFFFFF, &borrow);
    a[0] = subc(a[0], 0xFFFFFFFF, &borrow);
}

// Add P = 2^256 - 2^32 - 977
static inline void addP(unsigned int a[8])
{
    unsigned int carry = 0;
    a[7] = addc(a[7], 0xFFFFFC2F, &carry);
    a[6] = addc(a[6], 0xFFFFFFFE, &carry);
    a[5] = addc(a[5], 0xFFFFFFFF, &carry);
    a[4] = addc(a[4], 0xFFFFFFFF, &carry);
    a[3] = addc(a[3], 0xFFFFFFFF, &carry);
    a[2] = addc(a[2], 0xFFFFFFFF, &carry);
    a[1] = addc(a[1], 0xFFFFFFFF, &carry);
    a[0] = addc(a[0], 0xFFFFFFFF, &carry);
}

// Fast check: a >= P
static inline bool greaterThanEqualToP(const unsigned int a[8])
{
    if (a[0] < 0xFFFFFFFF) return false;
    if (a[1] < 0xFFFFFFFF) return false;
    if (a[2] < 0xFFFFFFFF) return false;
    if (a[3] < 0xFFFFFFFF) return false;
    if (a[4] < 0xFFFFFFFF) return false;
    if (a[5] < 0xFFFFFFFF) return false;
    if (a[6] < 0xFFFFFFFE) return false;
    if (a[6] > 0xFFFFFFFE) return true;
    return a[7] >= 0xFFFFFC2F;
}

// Compare two 256-bit numbers: a >= b
static inline bool isGreaterOrEqual256(uint256_t a, uint256_t b)
{
    for(int i = 0; i < 8; i++) {
        if(a.v[i] > b.v[i]) return true;
        if(a.v[i] < b.v[i]) return false;
    }
    return true;
}

// Unrolled 256x256 multiplication
// Optimized for register usage on AMD/NVIDIA
static inline void mulModP256k_internal(const unsigned int x[8], const unsigned int y[8], unsigned int r[8])
{
    unsigned int high[8];
    unsigned int low[8];
    unsigned int z[16] = {0};

    // Schoolbook multiplication (Fully unrolled with compiler hint to store z in registers)
    #pragma unroll
    for (int i = 7; i >= 0; i--) {
        unsigned int carry = 0;
        #pragma unroll
        for (int j = 7; j >= 0; j--) {
            unsigned long prod = (unsigned long)x[i] * y[j] + z[i + j + 1] + carry;
            z[i + j + 1] = (unsigned int)prod;
            carry = (unsigned int)(prod >> 32);
        }
        z[i] = carry;
    }

    #pragma unroll
    for(int i = 0; i < 8; i++) {
        high[i] = z[i];
        low[i] = z[8 + i];
    }

    // Efficient reduction for P = 2^256 - 2^32 - 977
    // Stage 1: Add high part shifted
    unsigned int hWord = 0;
    unsigned int carry = 0;
    #pragma unroll
    for(int i = 6; i >= 0; i--) low[i] = addc(low[i], high[i+1], &carry);
    unsigned int p7 = addc(high[0], 0, &carry);
    unsigned int p6 = carry;

    // Stage 2: Multiply high part by 977 and add
    carry = 0;
    hWord = 0;
    #pragma unroll
    for(int i = 7; i >= 0; i--) {
        unsigned int t;
        madd977(&hWord, &t, high[i], hWord);
        low[i] = addc(low[i], t, &carry);
    }
    p7 = addc(p7, hWord, &carry);
    p6 = addc(p6, 0, &carry);

    // Stage 3: Final normalization. Carry back p7 and p6 into the 256-bit 'low' part.
    // Identity: 2^256 = 2^32 + 977 (mod P)
    // p7 is at 2^256 position, p6 is at 2^288 position.

    unsigned long prod7 = (unsigned long)p7 * 977;
    unsigned int low7 = (unsigned int)prod7;
    unsigned int high7 = (unsigned int)(prod7 >> 32);

    unsigned long sum6 = (unsigned long)p7 + high7 + (unsigned long)p6 * 977;
    unsigned int low6 = (unsigned int)sum6;
    unsigned int high6 = (unsigned int)(sum6 >> 32);

    unsigned int sum5 = p6 + high6;

    unsigned int carry_val = 0;
    low[7] = addc(low[7], low7, &carry_val);
    low[6] = addc(low[6], low6, &carry_val);
    low[5] = addc(low[5], sum5, &carry_val);
    #pragma unroll
    for(int i = 4; i >= 0; i--) {
        low[i] = addc(low[i], 0, &carry_val);
    }

    if (carry_val) {
        unsigned int carry2 = 0;
        low[7] = addc(low[7], 977, &carry2);
        low[6] = addc(low[6], 1, &carry2);
        #pragma unroll
        for(int i = 5; i >= 0; i--) {
            low[i] = addc(low[i], 0, &carry2);
        }
    }

    while (greaterThanEqualToP(low)) subP(low);

    #pragma unroll
    for(int i = 0; i < 8; i++) r[i] = low[i];
}

uint256_t addModP256k(uint256_t a, uint256_t b)
{
    uint256_t c;
    unsigned int carry = 0;
    c.v[7] = addc(a.v[7], b.v[7], &carry);
    c.v[6] = addc(a.v[6], b.v[6], &carry);
    c.v[5] = addc(a.v[5], b.v[5], &carry);
    c.v[4] = addc(a.v[4], b.v[4], &carry);
    c.v[3] = addc(a.v[3], b.v[3], &carry);
    c.v[2] = addc(a.v[2], b.v[2], &carry);
    c.v[1] = addc(a.v[1], b.v[1], &carry);
    c.v[0] = addc(a.v[0], b.v[0], &carry);
    if(carry || greaterThanEqualToP(c.v)) subP(c.v);
    return c;
}

uint256_t subModP256k(uint256_t a, uint256_t b)
{
    uint256_t c;
    unsigned int borrow = 0;
    c.v[7] = subc(a.v[7], b.v[7], &borrow);
    c.v[6] = subc(a.v[6], b.v[6], &borrow);
    c.v[5] = subc(a.v[5], b.v[5], &borrow);
    c.v[4] = subc(a.v[4], b.v[4], &borrow);
    c.v[3] = subc(a.v[3], b.v[3], &borrow);
    c.v[2] = subc(a.v[2], b.v[2], &borrow);
    c.v[1] = subc(a.v[1], b.v[1], &borrow);
    c.v[0] = subc(a.v[0], b.v[0], &borrow);
    if(borrow) addP(c.v);
    return c;
}

uint256_t mulModP256k(uint256_t a, uint256_t b)
{
    uint256_t c;
    mulModP256k_internal(a.v, b.v, c.v);
    return c;
}

static inline void squareModP256k_internal(const unsigned int x[8], unsigned int r[8])
{
    unsigned int high[8];
    unsigned int low[8];
    unsigned int z[16] = {0};

    // 1. Compute cross-terms (28 multiplications)
    #pragma unroll
    for (int i = 7; i >= 0; i--) {
        unsigned int carry = 0;
        #pragma unroll
        for (int j = 7; j > i; j--) {
            unsigned long prod = (unsigned long)x[i] * x[j] + z[i + j + 1] + carry;
            z[i + j + 1] = (unsigned int)prod;
            carry = (unsigned int)(prod >> 32);
        }
        z[i + i + 1] = carry;
    }

    // 2. Double the cross-terms (shift left by 1 bit)
    unsigned int shift_carry = 0;
    #pragma unroll
    for (int i = 15; i >= 0; i--) {
        unsigned int next_carry = z[i] >> 31;
        z[i] = (z[i] << 1) | shift_carry;
        shift_carry = next_carry;
    }

    // 3. Add diagonal terms (8 multiplications)
    unsigned int add_carry = 0;
    #pragma unroll
    for (int i = 7; i >= 0; i--) {
        unsigned long diag = (unsigned long)x[i] * x[i];
        unsigned int d_low = (unsigned int)diag;
        unsigned int d_high = (unsigned int)(diag >> 32);

        z[2*i + 1] = addc(z[2*i + 1], d_low, &add_carry);
        z[2*i] = addc(z[2*i], d_high, &add_carry);
    }

    #pragma unroll
    for(int i = 0; i < 8; i++) {
        high[i] = z[i];
        low[i] = z[8 + i];
    }

    // 4. Efficient reduction for P = 2^256 - 2^32 - 977
    // Stage 1: Add high part shifted
    unsigned int hWord = 0;
    unsigned int carry = 0;
    #pragma unroll
    for(int i = 6; i >= 0; i--) low[i] = addc(low[i], high[i+1], &carry);
    unsigned int p7 = addc(high[0], 0, &carry);
    unsigned int p6 = carry;

    // Stage 2: Multiply high part by 977 and add
    carry = 0;
    hWord = 0;
    #pragma unroll
    for(int i = 7; i >= 0; i--) {
        unsigned int t;
        madd977(&hWord, &t, high[i], hWord);
        low[i] = addc(low[i], t, &carry);
    }
    p7 = addc(p7, hWord, &carry);
    p6 = addc(p6, 0, &carry);

    // Stage 3: Final normalization. Carry back p7 and p6 into the 256-bit 'low' part.
    unsigned long prod7 = (unsigned long)p7 * 977;
    unsigned int low7 = (unsigned int)prod7;
    unsigned int high7 = (unsigned int)(prod7 >> 32);

    unsigned long sum6 = (unsigned long)p7 + high7 + (unsigned long)p6 * 977;
    unsigned int low6 = (unsigned int)sum6;
    unsigned int high6 = (unsigned int)(sum6 >> 32);

    unsigned int sum5 = p6 + high6;

    unsigned int carry_val = 0;
    low[7] = addc(low[7], low7, &carry_val);
    low[6] = addc(low[6], low6, &carry_val);
    low[5] = addc(low[5], sum5, &carry_val);
    #pragma unroll
    for(int i = 4; i >= 0; i--) {
        low[i] = addc(low[i], 0, &carry_val);
    }

    if (carry_val) {
        unsigned int carry2 = 0;
        low[7] = addc(low[7], 977, &carry2);
        low[6] = addc(low[6], 1, &carry2);
        #pragma unroll
        for(int i = 5; i >= 0; i--) {
            low[i] = addc(low[i], 0, &carry2);
        }
    }

    while (greaterThanEqualToP(low)) subP(low);

    #pragma unroll
    for(int i = 0; i < 8; i++) r[i] = low[i];
}

uint256_t squareModP256k(uint256_t a)
{
    uint256_t c;
    squareModP256k_internal(a.v, c.v);
    return c;
}

uint256_t invModP256k(uint256_t a)
{
    uint256_t res = {{0,0,0,0,0,0,0,1}};
    uint256_t exp = {{0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFC2D}};
    uint256_t base = a;
    for(int i = 0; i < 256; i++) {
        unsigned int bit = (exp.v[7 - (i/32)] >> (i%32)) & 1;
        if(bit) res = mulModP256k(res, base);
        base = squareModP256k(base);
    }
    return res;
}

#endif
