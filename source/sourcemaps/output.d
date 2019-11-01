module sourcemaps.output;
import sourcemaps.vlq;

import std.array;
import std.json;

auto toSourceMap(DebugLines)(DebugLines lines, uint codeSectionOffset) {
  uint[string] sourceMap;
  Appender!(string[]) sources;
  Appender!(string[]) content;
  Appender!(string[]) mappings;

  struct State {
    long address;
    int sourceId;
    int line;
    int column;
    State opBinaryRight(string op : "-")(ref State rhs) {
      return State(address-rhs.address,
                   sourceId-rhs.sourceId,
                   line-rhs.line,
                   column-rhs.column
                   );
    }
    string toVlq() {
      auto app = appender!string;
      app.put(encodeVlq(address));
      app.put(encodeVlq(sourceId));
      app.put(encodeVlq(line));
      app.put(encodeVlq(column));
      return app.data;
    }
  }

  State prevState, state;
  foreach (line; lines) {
    foreach (program; line.programs) {
      foreach (address; program.addressInfo) {
        if (address.line == 0)
          continue;
        state.line = address.line;
        state.column = address.column;
        state.address = address.address + codeSectionOffset;
        auto filename = program.fileFromIndex(address.fileIndex);
        if (auto p = filename in sourceMap) {
          state.sourceId = (*p);
        } else {
          state.sourceId = cast(int)sources.data.length;
          sourceMap[filename] = state.sourceId;
          sources.put(filename);
          // maybe load sources...
        }
        auto delta = state - prevState;
        mappings.put(delta.toVlq);
        prevState = state;
      }
    }
  }
  // auto names= JSONValue().array;
  JSONValue[] names;
  return JSONValue(["version": JSONValue(3),
                    "names": JSONValue(names),
                    "souces": JSONValue(sources.data),
                    "mappings": JSONValue(mappings.data.join(","))
                    ]);
}
