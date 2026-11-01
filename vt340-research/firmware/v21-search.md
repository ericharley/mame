# VT330/VT340 V2.1 firmware search

## Result

No public V2.1 E1-E5 cartridge image or `EK-VT3XX-RN-003` release note has
been located. The matched V1.1 cartridge remains the only executable terminal
firmware available to this project.

DEC field-change order VT330-I001 identifies the replacement as cartridge
`70-22623-04 REV. C01`, labeled `VT330/340 V2.1`, and says that it corrects
multiple V1.1 firmware bugs. It does not enumerate those bugs. The later
field-service index repeats that V2.1 is a firmware-bug replacement but adds
no technical detail.

Sources:

- [DEC FCO VT330-I001](https://manx-docs.org/collections/mds-199909/cd2/fco/vt330i01.pdf)
- [DEC field-service FCO index](https://www.bitsavers.org/pdf/dec/fieldService/DEC_Datadoc_FS_Notes_Issue_42_199505/26_FCO_Information.pdf)

## Public firmware inventories checked

- [9track DEC ROM inventory](https://9track.net/roms/) has the VT340 E49
  character ROM, E80 NVR image, and three PAL dumps, but no E1-E5 V2.1 set.
- [OldPC DEC firmware inventory](https://oldpc.su/articles/dec_roms/) likewise
  has E80 and the PALs but no V2.1 cartridge set.
- Bitsavers VT340 firmware mirrors contain the same public V1.1 material.

## DECnotes archive result

The public `atlant::terminals` index preserves metadata for two directly
relevant discussions:

- topic 1191, `VT340 FIRMWARE DIFFERENCE V1.1 --> V2.1 ???`
- topic 2261, `VT330/340 ROM 70-22623-04`

The rendered site lists their replies but displays no bodies. Inspection of
the site's downloadable archive confirms why: conference 56 contains its
metadata files under `DATA/0056.*`, but the archive has no corresponding
`NT/0056.nt` note-body file. The missing replies cannot be recovered from the
published package.

Sources:

- [DECnotes terminal conference](https://decnotes.datacellar.net/showconf.php?conf=56)
- [DECnotes archive download description](https://decnotes.datacellar.net/download.html)

## Hardware inventory lead

An old commercial inventory lists part `70-22623-04`, but no contact or
purchase request has been made. Acquiring or dumping a physical V2.1
cartridge remains an external next step, not an emulator workaround.

If V2.1 becomes available, compare these locations first:

1. CPU1 `3ac9/3b64` report pacing and `3a08-3a3a` result-state routine.
2. CPU2's six `1701` rendezvous calls through `1322`.
3. CPU2 `1325-136d`, especially the table sequence preceding checkpoint zero.
4. The relative order of CPU1 pending `7ff2=10`, CPU2 checkpoint `00`, and
   CPU2 final result `80`.
