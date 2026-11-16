import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// SHA-256 özeti. iPhone'da CryptoKit kullanılır; CryptoKit olmayan yerde
/// (Linux'taki testler) aynı sonucu veren saf Swift sürümü.
public enum Ozet {
    public static func sha256Hex(_ metin: String) -> String {
        let bayt = Array(metin.utf8)
        #if canImport(CryptoKit)
        return hex(Array(SHA256.hash(data: Data(bayt))))
        #else
        return hex(saf(bayt))
        #endif
    }

    static func hex(_ bayt: [UInt8]) -> String {
        let rakam = Array("0123456789abcdef")
        var s = ""
        s.reserveCapacity(bayt.count * 2)
        for b in bayt {
            s.append(rakam[Int(b >> 4)])
            s.append(rakam[Int(b & 0x0f)])
        }
        return s
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// FIPS 180-4'teki SHA-256.
    static func saf(_ mesaj: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var veri = mesaj
        let bitUzunluk = UInt64(mesaj.count) * 8
        veri.append(0x80)
        while veri.count % 64 != 56 { veri.append(0) }
        for i in (0..<8).reversed() { veri.append(UInt8((bitUzunluk >> (UInt64(i) * 8)) & 0xff)) }

        func don(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

        var w = [UInt32](repeating: 0, count: 64)
        var blok = 0
        while blok < veri.count {
            for i in 0..<16 {
                let j = blok + i * 4
                w[i] = (UInt32(veri[j]) << 24) | (UInt32(veri[j + 1]) << 16) | (UInt32(veri[j + 2]) << 8) | UInt32(veri[j + 3])
            }
            for i in 16..<64 {
                let s0 = don(w[i - 15], 7) ^ don(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = don(w[i - 2], 17) ^ don(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = don(e, 6) ^ don(e, 11) ^ don(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = don(a, 2) ^ don(a, 13) ^ don(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            blok += 64
        }
        var cikti: [UInt8] = []
        cikti.reserveCapacity(32)
        for x in h {
            cikti.append(UInt8((x >> 24) & 0xff)); cikti.append(UInt8((x >> 16) & 0xff))
            cikti.append(UInt8((x >> 8) & 0xff)); cikti.append(UInt8(x & 0xff))
        }
        return cikti
    }
}
