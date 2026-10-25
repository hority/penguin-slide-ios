# Asset review

This private staging snapshot preserves all game runtime assets. Public redistribution remains pending review; this file does not grant a license.

- `Fonts/BIZUDPGothic-Bold.ttf`: BIZ UDPGothic, SIL Open Font License 1.1. The included notice is retained in `FontLicenses.txt`. The font bytes match the upstream Google Fonts repository version used by the original app.
- `Illustrations/*.png`: the repository contains an image-generation script for these game illustrations and title art. Generation provenance alone is not a completed redistribution-rights review.
- `Sounds/*.wav`: the sound-lab scripts define procedural sound effects and music. These are the original bundled WAV files, not newly regenerated output.
- `Models/Bluefish.bin`, `Pumpkin.bin`, `Sausage.bin`, `Lollipop.bin` and their textures, and `Illustrations/bluefish.png`, `pumpkin.png`, `sausage.png`, `lollipop.png`: the owner's favorite-food asset pack (geometry generated with Tripo Studio P2.0 from the owner's illustrations, textures made in Blender), simplified with gltfpack and converted by `ci/convert-food.py`. `Illustrations/finger.png` and `slide.png` come from `ci/generate-illustrations.py`. Confirm Tripo's output terms before publication.
- `Models/Penguin.bin`, `Octopus.bin`, `Ghost.bin`, `Unicorn.bin` and their textures: baked from the owner's P2 character masters (kept outside the repository) by `ci/bake-character.py` (Blender 5.0 as a Python module and gltfpack), with the rig weights stored in the model.
- Other `Models/*` and `Stage/*`: runtime mesh and texture files preserved unchanged. Editable design masters are excluded from this source-only snapshot. Confirm the original generation/source terms and redistribution rights before publication.
- `Assets.xcassets/AppIcon.appiconset/AppIcon.png`: retained unchanged; confirm its provenance before publication.

No blanket open-source license is included. Confirm ownership and intended licensing before making this repository public. No certificates, private keys, provisioning profiles, original Git history or private session links are included in this source snapshot.

- `Models/Rabbit.bin`, `Dolphinchibi.bin`, `Rhino.bin`, `Orca.bin`, their base/normal/roughness maps and corresponding selection illustrations: derived from four private Tripo H3.1 textured outputs matching the owner's supplied reference. See `TRIPO-CHARACTERS.md` for original Library identities, conversion, animation, and verification limits. Existing scenery dolphin assets are unchanged. No new public redistribution permission is implied.
