import std.stdio;
import wasm_reader.reader;
import wasm_reader.leb;
import dwarf.debugline;
import dwarf.debugabbrev;
import dwarf.debuginfo;
import std.conv;

import std.algorithm : map, filter, joiner, each;
import std.range : drop, take;
import std.format;
import sourcemaps.output;
import std.array;
import std.file;
import std.path;
import std.process;
import darg;

struct Options
{
  @Option("help", "h")
  @Help("Prints this help.")
  OptionFlag help;

  @Argument("file")
  @Help("Input file")
  string input;

  @Option("output")
  @Help("Output file, default is same as input with '.map' extension added, use '-' for stdout")
  string output;

  @Option("embed")
  @Help("embeds the sourcemap url in wasm file. Default is true. This adds a sourceMappingURL custom section in the wasm file with a reference to the sourcemap file. This allows browsers to automatically load the sourcemap file.")
  bool embed = true;

  @Option("embed-base-url")
  @Help("sets the url used when embedding the sourcemap url in the webassembly file. Default is './'.")
  string embedBaseUrl;

  @Option("include-sources")
  @Help("includes the source files in the sourcemap. Default is 'false'.")
  bool includeSources;
}

auto getOutputFile(ref Options options) {
  if (options.output == "-")
    return stdout;
  if (options.output == "")
    options.output = options.input~".map";
  return File(options.output,"w");
}

auto getSourceMappingUrl(ref Options options) {
  auto output = options.output;
  if (options.embedBaseUrl.length > 0)
    return options.embedBaseUrl ~ "/" ~ output;
  return "./"~output;
}

immutable usage = usageString!Options("wasm-sourcemaps");
immutable help = helpString!Options;

enum sourceMappingUrlName = "sourceMappingURL";

int main(string[] args)
{
  Options options;

  try {
    options = parseArgs!Options(args[1 .. $]);
  }
  catch (ArgParseError e) {
    writeln(e.msg);
    writeln(usage);
    return 1;
  }
  catch (ArgParseHelp e) {
    writeln(usage);
    write(help);
    return 0;
  }

  if (!exists(options.input)) {
    writefln("Error: File %s doesn't exist", args[1]);
    return 1;
  }

  DebugLine line;
  DebugAbbrev abbrev;
  ubyte[] infoPayload;
  ubyte[] strs;
  uint codeOffset = 8;
  bool foundCodeOffset = false;
  bool hasSourceMappingSection = false;

  {
    auto input = File(options.input).byChunk(4096).joiner().drop(8);
    foreach(section; input.readSections) {
      if (section.id == 10) {
        foundCodeOffset = true;
        codeOffset += 1 + sizeOf!(varuint32)(section.payload_len);
      } else if (!foundCodeOffset)
        codeOffset += section.size();
      if (section.name == ".debug_line")
        line = DebugLine(section.payload);
      else if (section.name == ".debug_abbrev")
        abbrev = DebugAbbrev(section.payload);
      else if (section.name == ".debug_info")
        infoPayload = section.payload;
      else if (section.name == ".debug_str")
        strs = section.payload;
      else if (section.name == sourceMappingUrlName)
        hasSourceMappingSection = true;
    }
  }

  DebugInfo info = DebugInfo(infoPayload, abbrev.tags, strs);
  auto output = line.toSourceMap(info, codeOffset, options.embed, options.embedBaseUrl, options.includeSources);
  options.getOutputFile().write(output);
  if (options.embed) {
    if (hasSourceMappingSection) {
      stderr.writefln("Error: cannot embed. File %s already has an sourceMappingURL section", options.input);
      return 1;
    }
    string sourceMappingUrl = options.getSourceMappingUrl();
    auto appendFile = File(options.input, "ab");
    appendFile.rawWrite([cast(ubyte)0]);
    appendFile.rawWrite([cast(ubyte)(sourceMappingUrl.length + 2 + sourceMappingUrlName.length)]);
    appendFile.rawWrite([cast(ubyte)sourceMappingUrlName.length]);
    appendFile.write(sourceMappingUrlName);
    appendFile.rawWrite([cast(ubyte)(sourceMappingUrl.length)]);
    appendFile.write(sourceMappingUrl);
  }
  return 0;
}
