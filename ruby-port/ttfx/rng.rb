# Faithful xoshiro256++ engine RNG (ttfx src/utils/rng.rs).
#
# Spinel integers are fixed-width 64-bit words and the default
# --int-overflow=raise mode refuses silent wraparound, so the 64-bit state
# is emulated as 16-bit limbs: every intermediate stays below 2^34 and the
# sequence is bit-identical in CRuby and in the Spinel binary.
# Helper semantics mirror Python random: randint inclusive, randrange
# half-open, choice, shuffle (Fisher-Yates from the top), random/uniform.
class Rng
  M16 = 0xffff

  def initialize(seed)
    @s0 = seed_limbs(seed)
    @s1 = [0, 0, 0, 0]
    @s2 = [0, 0, 0, 0]
    @s3 = [0, 0, 0, 0]
    sm = seed_limbs(seed)
    @s0 = splitmix_next(sm)
    @s1 = splitmix_next(sm)
    @s2 = splitmix_next(sm)
    @s3 = splitmix_next(sm)
  end

  def self.seeded(seed)
    Rng.new(seed)
  end

  # ---- limb helpers (little-endian 4x16-bit words) ----

  def seed_limbs(v)
    [v & M16, (v >> 16) & M16, (v >> 32) & M16, (v >> 48) & M16]
  end

  def add64(a, b)
    r0 = a[0] + b[0]
    r1 = a[1] + b[1] + (r0 >> 16)
    r0 &= M16
    r2 = a[2] + b[2] + (r1 >> 16)
    r1 &= M16
    r3 = a[3] + b[3] + (r2 >> 16)
    r2 &= M16
    r3 &= M16
    [r0, r1, r2, r3]
  end

  def xor64(a, b)
    [a[0] ^ b[0], a[1] ^ b[1], a[2] ^ b[2], a[3] ^ b[3]]
  end

  def shl64(a, k)
    ws = k / 16
    bs = k % 16
    r = [0, 0, 0, 0]
    i = 0
    while i < 4
      v = 0
      j = i - ws
      if j >= 0
        v |= a[j] << bs
        v |= a[j - 1] >> (16 - bs) if bs > 0 && j - 1 >= 0
      end
      r[i] = v & M16
      i += 1
    end
    r
  end

  def shr64(a, k)
    ws = k / 16
    bs = k % 16
    r = [0, 0, 0, 0]
    i = 0
    while i < 4
      v = 0
      j = i + ws
      if j < 4
        v |= a[j] >> bs
        v |= (a[j + 1] & M16) << (16 - bs) if bs > 0 && j + 1 < 4
      end
      r[i] = v & M16
      i += 1
    end
    r
  end

  def or64(a, b)
    [a[0] | b[0], a[1] | b[1], a[2] | b[2], a[3] | b[3]]
  end

  def rotl64(a, k)
    or64(shl64(a, k), shr64(a, 64 - k))
  end

  def mul64(a, b)
    r = [0, 0, 0, 0]
    i = 0
    while i < 4
      j = 0
      while j < 4 - i
        r[i + j] = r[i + j] + a[i] * b[j]
        j += 1
      end
      i += 1
    end
    i = 0
    while i < 3
      r[i + 1] = r[i + 1] + (r[i] >> 16)
      r[i] &= M16
      i += 1
    end
    r[3] &= M16
    r
  end

  # SplitMix64: seed expansion into the xoshiro state.
  # sm += 0x9E3779B97F4A7C15 (limbs), wrapping at 64 bits.
  def splitmix_next(sm)
    carry = 0
    inc = [0x7c15, 0x7f4a, 0x79b9, 0x9e37]
    i = 0
    while i < 4
      s = sm[i] + inc[i] + carry
      sm[i] = s & M16
      carry = s >> 16
      i += 1
    end
    z = [sm[0], sm[1], sm[2], sm[3]]
    z = xor64(z, shr64(z, 30))
    z = mul64(z, [0xe5b9, 0x1ce4, 0x476d, 0xbf58])
    z = xor64(z, shr64(z, 27))
    z = mul64(z, [0x11eb, 0x1331, 0x49bb, 0x94d0])
    z = xor64(z, shr64(z, 31))
    z
  end

  # Core generator: xoshiro256++ next(), returned as limbs.
  def next_word
    r = add64(rotl64(add64(@s0, @s3), 23), @s0)
    t = shl64(@s1, 17)
    @s2 = xor64(@s2, @s0)
    @s3 = xor64(@s3, @s1)
    @s1 = xor64(@s1, @s2)
    @s0 = xor64(@s0, @s3)
    @s2 = xor64(@s2, t)
    @s3 = rotl64(@s3, 45)
    r
  end

  def bitlen(v)
    n = 0
    while v > 0
      n += 1
      v >>= 1
    end
    n
  end

  # Uniform integer in [0, n): bitmask rejection, one u64 per attempt.
  def randbelow(n)
    raise "randbelow(0)" if n <= 0
    bl = bitlen(n - 1)
    bl = 1 if bl < 1
    shift = 64 - bl
    loop do
      w = shr64(next_word, shift)
      v = w[0] + (w[1] << 16)
      v += w[2] << 32 if bl > 32
      v += w[3] << 48 if bl > 48
      return v if v < n
    end
  end

  def randint(a, b)
    a + randbelow(b - a + 1)
  end

  def randrange(a, b)
    a + randbelow(b - a)
  end

  def choice_index(n)
    randbelow(n)
  end

  def choice(seq)
    seq[randbelow(seq.length)]
  end

  def shuffle(seq)
    i = seq.length - 1
    while i >= 1
      j = randbelow(i + 1)
      tmp = seq[i]
      seq[i] = seq[j]
      seq[j] = tmp
      i -= 1
    end
    seq
  end

  # Python random.random(): float in [0, 1) with 53 bits.
  def random
    w = next_word
    hi = w[2] + (w[3] << 16)
    lo = w[0] + (w[1] << 16)
    v = (hi << 21) | (lo >> 11)
    v.to_f / 9007199254740992.0
  end

  def uniform(a, b)
    a + (b - a) * random
  end

  # ---- legacy compat (simplified effects still use these) ----
  def below(n)
    return 0 if n <= 1
    randbelow(n)
  end

  def range(a, b)
    randint(a, b)
  end

  def float
    random
  end

  def next_int
    w = next_word
    w[0] + (w[1] << 16)
  end
end
