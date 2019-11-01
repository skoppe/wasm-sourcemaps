import std.stdio;
import wasm_reader.reader;
import dwarf.debugline;
import std.conv;

import std.algorithm : map, filter, joiner;
import std.range : drop, take;
import std.format;
import sourcemaps.output;
import std.array;
import std.file;
import std.process;

int main(string[] args)
{
  if (args.length < 2) {
    writeln("Error: Supply WebAssembly file as first argument");
    return 1;
  }
  if (!exists(args[1])) {
    writefln("Error: File %s doesn't exist", args[1]);
    return 1;
  }

  auto input = File(args[1]).byChunk(4096).joiner().drop(8);
  auto lines = appender!(DebugLine[]);
  uint codeOffset = 0;
  bool foundCodeOffset = false;

  foreach(section; input.readSections) {
    if (section.id == 10)
      foundCodeOffset = true;
    else if (!foundCodeOffset)
      codeOffset += section.size();
    if (section.name == ".debug_line")
      lines.put(DebugLine(section.payload));
  }

  auto output = lines.data.toSourceMap(codeOffset);
  writeln(output);
  return 0;
}
