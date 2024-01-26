module wasm_sourcemaps.dwarf.debuginfo;
// this implementation follows the DWARF v4 documentation

import std.exception;
import std.range;
import std.conv : to;
import wasm_sourcemaps.dwarf.meta;
import wasm_sourcemaps.dwarf.elf;
import wasm_sourcemaps.dwarf.debugabbrev;

import std.stdio;
import std.format;
import std.algorithm;

struct DebugInfo {
  private Appender!(CompilationUnit[]) units_;

  private enum uint DWARF_64BIT_FLAG = 0xffff_ffff;

  this(ubyte[] contents, const(Tag[ULEB128]) tags, ubyte[] strs) {
    while (!contents.empty) {
      CompilationUnit unit;

      ubyte[] nextUnit;
      // detect dwarf 32bit or 64bit
      uint initialLength = * cast(uint*) contents.ptr;
      unit.is64bit = (*cast(uint*) contents.ptr) == DWARF_64BIT_FLAG;
      if (unit.is64bit) {
        contents.popFrontExactly(uint.sizeof); // skip 64bit marker
        unit.unitLength = contents.read!(ulong);
        nextUnit = contents[unit.unitLength .. $];
        unit.dwarfVersion = contents.read!(ushort);
        unit.debugAbbrevOffset = contents.read!(ulong);
        unit.addressSize = contents.read!(ubyte);
      } else {
        unit.unitLength = contents.read!(uint);
        nextUnit = contents[unit.unitLength .. $];
        unit.dwarfVersion = contents.read!(ushort);
        unit.debugAbbrevOffset = contents.read!(uint);
        unit.addressSize = contents.read!(ubyte);
      }

      auto tagCode = contents.readULEB128;
      auto tag = tags[tagCode];
      if (tag.name == TagEncoding.compileUnit) {
        unit.attributes = tag.attributes.map!((attribute){
            return RawAttribute(attribute.name,
                                attribute.form,
                                contents.readRawAttribute(attribute.form, unit));
          }).array();
      }
      unit.strs = strs;
      units_.put(unit);
      contents = nextUnit;
    }
  }

  const(CompilationUnit)[] units() { return units_.data; }
}

auto readBytes(ref ubyte[] contents, size_t length) {
  ubyte[] bytes = contents[0 .. length];
  contents.popFrontExactly(length);
  return bytes;
}
auto readRawULEB128(ref ubyte[] contents) {
  size_t len = 0;
  for (;;) {
    if (contents[len++] < 0xA0)
      return contents.readBytes(len);
  }
}
auto readRawString(ref ubyte[] contents) {
  size_t len = 0;
  for (;;) {
    if (contents[len] == 0)
      return contents.readBytes(len);
    else
      len++;
  }
}
alias readRawSLEB128 = readRawULEB128;
auto readRawAttribute(ref ubyte[] contents, const ref AttributeForm form, ref CompilationUnit unit) {
  final switch(form) with (AttributeForm) {
    case addr: return contents.readBytes(unit.addressSize);
    case block2: auto len = contents.read!(ushort); return contents.readBytes(len);
    case block4: auto len = contents.read!(uint); return contents.readBytes(len);
    case data2: return contents.readBytes(2);
    case data4: return contents.readBytes(4);
    case data8: return contents.readBytes(8);
    case string_: return contents.readRawString();
    case block: auto len = contents.readULEB128; return contents.readBytes(len);
    case block1: auto len = contents.read!(ubyte); return contents.readBytes(len);
    case data1: return contents.readBytes(1);
    case flag: return contents.readBytes(1);
    case sdata: return contents.readRawSLEB128();
    case strp: return contents.readBytes(uint.sizeof);
    case udata: return contents.readRawULEB128();
    case refAddr: return contents.readBytes(unit.is64bit ? 8 : 4);
    case ref1: return contents.readBytes(1);
    case ref2: return contents.readBytes(2);
    case ref4: return contents.readBytes(4);
    case ref8: return contents.readBytes(8);
    case refUdata: return contents.readRawULEB128();
    case indirect: auto indirectForm = cast(AttributeForm)contents.readULEB128; return contents.readRawAttribute(indirectForm, unit);
    case secOffset: return contents.readBytes(unit.is64bit ? 8 : 4);
    case exprLoc: auto len = contents.readULEB128; return contents.readBytes(len);
    case flagPresent: return contents[0 .. 0];
    case refSig8: return contents.readRawULEB128();
    }
}

struct RawAttribute {
  AttributeName name;
  AttributeForm form;
  ubyte[] payload;
}

struct CompilationUnit {
  ulong unitLength;
  ushort dwarfVersion;
  ulong debugAbbrevOffset;
  ubyte addressSize;
  bool is64bit;
  RawAttribute[] attributes;
  ubyte[] strs;
}

auto loadStrp(const ref CompilationUnit unit, const(ubyte[]) rawOffset) {
  uint offset = *cast(uint*)&rawOffset[0];
  return (cast(char*)unit.strs[offset..$].ptr).to!string();
}

auto getCompDir(const ref CompilationUnit unit) {
  auto range = unit.attributes.filter!(a => a.name == AttributeName.compDir).map!(raw => unit.loadStrp(raw.payload));
  if (range.empty)
    throw new Error("Failed to find compDir in CompilationUnit");
  return range.front();
}

private T read(T)(ref ubyte[] buffer) {
  T result = *(cast(T*) buffer[0 .. T.sizeof].ptr);
  buffer.popFrontExactly(T.sizeof);
  return result;
}

private ulong readULEB128(ref ubyte[] buffer) {
  import std.array;
  ulong val = 0;
  ubyte b;
  uint shift = 0;

  while (true) {
    b = buffer.read!ubyte();

    val |= (b & 0x7f) << shift;
    if ((b & 0x80) == 0) break;
    shift += 7;
  }

  return val;
}

unittest {
  ubyte[] data = [0xe5, 0x8e, 0x26, 0xDE, 0xAD, 0xBE, 0xEF];
  assert(readULEB128(data) == 624_485);
  assert(data[] == [0xDE, 0xAD, 0xBE, 0xEF]);
}

private long readSLEB128(ref ubyte[] buffer) {
  import std.array;
  long val = 0;
  uint shift = 0;
  ubyte b;
  int size = 8 << 3;

  while (true) {
    b = buffer.read!ubyte();
    val |= (b & 0x7f) << shift;
    shift += 7;
    if ((b & 0x80) == 0)
      break;
  }

  if (shift < size && (b & 0x40) != 0) val |= -(1 << shift);
  return val;
}
