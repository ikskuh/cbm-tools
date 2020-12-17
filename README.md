# CBM Tools

My collection of smaller tools related to [commodore business machines](https://de.wikipedia.org/wiki/Commodore_International).

## `cbm-basic`

`cbm-basic` is a simple tokenizer/detokenizer to convert your BASIC `PRG` files into plain text files or back.

**Usage:**
```
cbm-basic [fileName]
Supported command line arguments:
  -h, --help                 Prints this help text.
      --start-address [num]  Defines the load address of the basic program. [num] is decimal (default) or hexadecimal (when prefixed).
  -o, --output [file]        Sets the output file to [file] when given.
  -m, --mode [mode]          Sets the mode to `compile` or `decompile`.
  -d, --device [dev]         Sets the device. Supported devices are listed below.
  -V, --version [vers]       Sets the used basic version. Supported basic versions are listed below.

In `compile` mode, the application will read BASIC code from stdin or [fileName] when given and will tokenize it into a CBM readable format.
Each line in the input must have a decimal line number followed by several characters. The input encoding is assumed to be PETSCII.

In `decompile` mode the application will read in a BASIC PRG file and will output detokenized BASIC code.
Each line in the output will be prefixed by a decimal line number and a space. The output encoding is assumed to be PETSCII.

Supported devices:
  c64, c128

Supported BASIC versions:
  1.0, 2.0, 3.5, 7.0
```