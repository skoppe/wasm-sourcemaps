import std.stdio;
import wasm_reader.reader;
import wasm_reader.leb;
import wasm_sourcemaps.dwarf.debugline;
import wasm_sourcemaps.dwarf.debugabbrev;
import wasm_sourcemaps.dwarf.debuginfo;
import wasm_sourcemaps.generate;
import std.conv;

import std.algorithm : map, filter, joiner, each;
import std.range : drop, take;
import std.format;
import wasm_sourcemaps.sourcemaps.output;
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

auto getOutputFile(ref Options options) 
{
  return wasm_sourcemaps.generate.getOutputFile(options.output, options.input);
}

auto getSourceMappingUrl(ref Options options) {
  return wasm_sourcemaps.generate.getSourceMappingUrl(options.output, options.embedBaseUrl);
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
  string[] errors;

  bool ret = generateSourceMaps(options.output, options.input, options.embedBaseUrl, options.embed, options.includeSources, errors);

  foreach(err; errors)
    stderr.writeln(err);
  return ret ? 0 : 1;

}
