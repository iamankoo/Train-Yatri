/// A tiny in-memory TTL cache plus in-flight request de-duplication -
/// Block 6's rate-protection requirements (Part 14, 16), without a
/// Redis/memcached dependency this single small service doesn't need.
/// Deliberately process-local: if this ever runs as more than one
/// instance, each instance's cache is independent, which only means a
/// slightly higher (still bounded) worst-case request rate to
/// RailRadar - never incorrect behavior.
export class TtlCache {
  constructor({ ttlMs, now = () => Date.now() }) {
    this.ttlMs = ttlMs;
    this.now = now;
    this.entries = new Map(); // key -> { value, expiresAt }
    this.inFlight = new Map(); // key -> Promise<value>
  }

  get(key) {
    const entry = this.entries.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt <= this.now()) {
      this.entries.delete(key);
      return undefined;
    }
    return entry.value;
  }

  set(key, value) {
    this.entries.set(key, { value, expiresAt: this.now() + this.ttlMs });
  }

  /// Returns the cached value if fresh; otherwise runs [loader] exactly
  /// once even if called concurrently for the same [key] (Block 6 Part
  /// 4/16: "avoid duplicate concurrent requests where practical") -
  /// every concurrent caller for the same key awaits the same in-flight
  /// upstream call instead of each firing its own.
  async getOrLoad(key, loader) {
    const cached = this.get(key);
    if (cached !== undefined) return { value: cached, cacheHit: true };

    const existing = this.inFlight.get(key);
    if (existing) return { value: await existing, cacheHit: true };

    const promise = (async () => {
      try {
        const value = await loader();
        this.set(key, value);
        return value;
      } finally {
        this.inFlight.delete(key);
      }
    })();
    this.inFlight.set(key, promise);
    return { value: await promise, cacheHit: false };
  }
}
