# CBM Tools

My collection of smaller tools related to [commodore business machines](https://de.wikipedia.org/wiki/Commodore_International).

## `cbm-basic`

`cbm-basic` is a simple tokenizer/detokenizer to convert your BASIC `PRG` files into plain text files or back.

**Usage:**
```
cbm-basic -m compile < my-file.bas > MY-FILE.PRG
cbm-basic -m decompile < MY-FILE.PRG > my-file.bas
```