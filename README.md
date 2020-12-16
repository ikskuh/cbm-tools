# CBM Tools

My collection of smaller tools related to [commodore business machines](https://de.wikipedia.org/wiki/Commodore_International).

## `cbm-basic`

`cbm-basic` is a simple tokenizer/detokenizer to convert your BASIC `PRG` files into plain text files or back.

**Usage:**
```
cbm-basic --mode compile < my-file.bas > my-file.prg
cbm-basic --mode decompile < my-file.prg > my-file.bas
```