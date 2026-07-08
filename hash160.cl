#ifndef _HASH160_CL
#define _HASH160_CL

#include "sha256.cl"
#include "ripemd160.cl"

static inline unsigned int hash160Endian(unsigned int x)
{
    return (x << 24) | ((x << 8) & 0x00ff0000) | ((x >> 8) & 0x0000ff00) | (x >> 24);
}

static inline void hash160WordsToBytes(const unsigned int digest[5], uchar out[20])
{
    for(int i = 0; i < 5; i++) {
        out[i * 4 + 0] = (uchar)((digest[i] >> 0) & 0xff);
        out[i * 4 + 1] = (uchar)((digest[i] >> 8) & 0xff);
        out[i * 4 + 2] = (uchar)((digest[i] >> 16) & 0xff);
        out[i * 4 + 3] = (uchar)((digest[i] >> 24) & 0xff);
    }
}

static inline void hash160CompressedBytes(uint256_t x, uint256_t y, uchar out[20])
{
    unsigned int sha[8];
    unsigned int digest[5];
    unsigned int parity = y.v[7] & 1U;

    sha256PublicKeyCompressed(x.v, parity, sha);

    for(int i = 0; i < 8; i++) {
        sha[i] = hash160Endian(sha[i]);
    }

    ripemd160sha256(sha, digest);
    hash160WordsToBytes(digest, out);
}

static inline bool hash160CompressedMatches(uint256_t x, uint256_t y, __constant const uchar* targetHash160)
{
    uchar hash[20];
    hash160CompressedBytes(x, y, hash);

    for(int i = 0; i < 20; i++) {
        if(hash[i] != targetHash160[i]) return false;
    }

    return true;
}

static inline bool hash160PrefixMatches(const uchar hash[20], __constant const uchar* targetHash160, int prefixLen)
{
    for(int i = 0; i < prefixLen; i++) {
        if(hash[i] != targetHash160[i]) return false;
    }

    return true;
}

static inline bool hash160FullMatches(const uchar hash[20], __constant const uchar* targetHash160)
{
    for(int i = 0; i < 20; i++) {
        if(hash[i] != targetHash160[i]) return false;
    }

    return true;
}

#endif
