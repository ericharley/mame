# VT340 reference collection

Copied into the research tree on 2026-11-04. These are local copies of the
existing reference material; the original files remain in place. No documents
were fetched or revised as part of this copy.

## Main references

- [VT340 schematic drawing set](schematics/K-TC-VT340_Schematic_Feb87.pdf):
  board schematics, particularly terminal control module PDF pages 18–27.
- [Pocket Service Guide](manuals/ek-vt340-ps-002.pdf).
- [Intel 8031AH/8032AH data sheet, order 270499-006](datasheets/intel-270499-006-8031ah-8032ah.pdf).
- [Dragon Video System Hardware Specification](library/kindred/Dragon_Video_System_Hardware_Specification_4.2_Jun85.pdf).
- [DEC Adder Address Processor](<library/kindred/DEC Adder Address Processor 1986.pdf>).
- [DEC Viper Video Processor](<library/kindred/DEC Viper Video Processor 1986.pdf>).
- [VT330/VT340 User's Guide](library/EK-VT3XX-UG-002_VT330_VT340_Users_Guide_May88.pdf).
- [VT330/VT340 Graphics Programming](library/EK-VT3XX-GP-002_VT330_VT340_Graphics_Programming_May88.pdf).
- [VT330/VT340 Programmer Pocket Guide](library/EK-VT3XX-HR-002_VT330_VT340_Programmer_Pocket_Guide_May88.pdf).
- [Level 2 SIXEL Programming Reference](library/EK-PPLV2-PM.B01_Level_2_Sixel_Programming_Reference.pdf).
- [VT340A Field Maintenance Print Set](library/hardware/MP-02412-01_VT340A_Field_Maintenance_Print_Set_Feb87.pdf).
- [VT340 Internals archived page](archive/avitech-vt340.html),
  [cartridge photograph](archive/cartridge-connector.tif), and
  [cartridge wiring table](archive/cartridge-internal-wiring.docx).

## Directory layout

| Directory | Contents |
| --- | --- |
| `schematics/` | Main VT340 schematic drawing set |
| `manuals/` | Standalone service manual |
| `datasheets/` | Standalone processor data sheet |
| `archive/` | Archived source page, cartridge image, and wiring document |
| `pal/` | Three JEDEC PAL dumps used in address-decoding analysis |
| `library/` | Complete existing `vt340test/docs` reference library, preserving its hardware, kindred, standards, and other subdirectories |
| `working-extracts/` | Existing PDFs, rendered pages, crops, and text extracts from `tmp/pdfs`, preserved for traceability |

The library includes related terminals, printers, character sets, and standards;
not every document is primary VT340 hardware evidence. Working extracts may be
partial or have imperfect OCR. Use the original scanned manuals as authority.
The archived HTML is a saved page; linked external resources are not necessarily
available offline.

## Provenance and integrity

[manifest.json](manifest.json) records each copied file's path, original
workspace-relative source location, byte count, and SHA-256. Every destination
was compared against its source checksum during copying. Identical documents
may appear under different original names; their checksums identify duplicates.

This collection excludes firmware ROM binaries, emulator build outputs, the
full test-source checkout, and temporary execution logs. ROM provenance remains
in `../firmware/manifest.json`; test-corpus provenance remains in `../tests/`.
Copying a reference does not change its original ownership or license.
