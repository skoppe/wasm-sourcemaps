module sourcemaps.vlq;

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
  writeln(5.encodeVlq);
}
