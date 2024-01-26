module wasm_sourcemaps.sourcemaps.vlq;

auto encodeVlq(long n) {
  enum chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  long x = n >= 0 ? n << 1 : ((-n << 1) + 1);
  string r;
  for(;;) {
    if (x > 31) {
      r ~= chars[32 + (x & 31)];
      x = x >> 5;
    } else {
      r ~= chars[x];
      return r;
    }
  }
}

unittest {
  import std.stdio;
  assert(5.encodeVlq == "K");
  assert(125.encodeVlq == "6H");
  assert(0.encodeVlq ==	"A");
  assert(1.encodeVlq == "C");
  assert(encodeVlq(-1) == "D");
  assert(123.encodeVlq == "2H");
  assert(123456789.encodeVlq == "qxmvrH");
}
