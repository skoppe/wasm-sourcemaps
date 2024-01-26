module wasm_sourcemaps.generate;
import wasm_reader.reader;
import wasm_reader.leb;
import wasm_sourcemaps.sourcemaps.output;
import wasm_sourcemaps.dwarf.debuginfo;
import wasm_sourcemaps.dwarf.debugline;
import wasm_sourcemaps.dwarf.debugabbrev;
import std.stdio;
import std.file;
import std.algorithm;
import std.process;
import std.range;

enum sourceMappingUrlName = "sourceMappingURL";

auto getOutputFile(string outputPath, string inputPath) {
  if (outputPath == "-")
    return stdout;
  if (outputPath == "")
    outputPath = inputPath~".map";
  return File(outputPath,"w");
}

auto getSourceMappingUrl(string outputPath, string embedBaseUrl = null) 
{
  if (embedBaseUrl.length > 0)
    return embedBaseUrl ~ "/" ~ outputPath;
  return "./"~outputPath;
}

/** 
 * 
 * Params:
 *   outputPath = Output file, default is same as input with '.map' extension added, use '-' for stdout
 *   inputPath = Input File
 *   embedBaseUrl = sets the url used when embedding the sourcemap url in the webassembly file. Default is './'.
 *   shouldEmbed = embeds the sourcemap url in wasm file. This adds a sourceMappingURL custom section in the wasm file with a reference to the sourcemap file. This allows browsers to automatically load the sourcemap file.
 *   includeSources = includes the source files in the sourcemap
 * Returns: 
 */
bool generateSourceMaps(string outputPath, string inputPath, string embedBaseUrl, bool shouldEmbed = true, bool includeSources = false, out string[] errors)
{
    if (!exists(inputPath)) {
        errors~= "Error: File "~inputPath~" doesn't exist";
        return false;
    }
    DebugLine line;
    DebugAbbrev abbrev;
    ubyte[] infoPayload;
    ubyte[] strs;
    uint codeOffset = 8;
    bool foundCodeOffset = false;
    bool hasSourceMappingSection = false;

    {
        auto input = File(inputPath).byChunk(4096).joiner().drop(8);
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
    auto output = line.toSourceMap(info, codeOffset, shouldEmbed, embedBaseUrl, includeSources);
    getOutputFile(outputPath, inputPath).write(output);
    if (shouldEmbed) {
        if (hasSourceMappingSection) {
            errors~= "Error: cannot embed. File "~inputPath~" already has an sourceMappingURL section";
            return false;
        }
        string sourceMappingUrl = getSourceMappingUrl(outputPath, embedBaseUrl);
        auto appendFile = File(inputPath, "ab");
        appendFile.rawWrite([cast(ubyte)0]);
        appendFile.rawWrite([cast(ubyte)(sourceMappingUrl.length + 2 + sourceMappingUrlName.length)]);
        appendFile.rawWrite([cast(ubyte)sourceMappingUrlName.length]);
        appendFile.write(sourceMappingUrlName);
        appendFile.rawWrite([cast(ubyte)(sourceMappingUrl.length)]);
        appendFile.write(sourceMappingUrl);
    }
    return true;
}