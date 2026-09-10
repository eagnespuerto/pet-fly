# PetFly credits

The PetFly **source code** is MIT licensed (see [LICENSE](LICENSE)).

The bundled **assets are not** — they keep the licences below, and the three
CC-BY fly models require attribution when you redistribute the game. This file
and the in-game credits screen (`C`) provide it.

## Brain data — Virtual Fly Brain

Neuroanatomy in PetFly is real. Every circuit in the brain panel is a neuron
population from [Virtual Fly Brain](https://virtualflybrain.org), retrieved with
the [`vfb_connect`](https://github.com/VirtualFlyBrain/VFB_connect) API and built
on the Drosophila Anatomy Ontology (FBbt) plus published connectome datasets.

- Bundled snapshot: `assets/data/vfb_brain.json`, harvested by the Python
  `tools/harvest_vfb.py` (8 circuits, 267 neuron classes, 80 individual
  reconstructions, plus neurotransmitter predictions from 1,646 cells).
- Live queries: the game can re-query virtualflybrain.org at runtime.
- Individual neurons carry their own dataset licences, shown on their VFB report
  pages. Open any neuron in-game with **OPEN IN VFB**.

Neurotransmitter predictions in the bundle cite FlyBase:FBrf0259490,
doi:10.7554/eLife.97769.1 and doi:10.1101/2025.10.09.680999.

## Fly models

All four are free downloads from [Poly Pizza](https://poly.pizza). Press **M**
in game to cycle between them.

| Model | Author | Licence | Source |
|---|---|---|---|
| `fly_kohyzazi_cc0.glb` (default) | Kohyzazi | **CC0** — public domain | https://poly.pizza/m/kCLW4c0kGx |
| `fly_google_ccby.glb` | Poly by Google | **CC-BY 3.0** | https://poly.pizza/m/c7w1u4mSnXZ |
| `fly_aronia_ccby.glb` | AroniaStudios | **CC-BY 3.0** | https://poly.pizza/m/tPHgsoiRCZ |
| `fly_jeremy_ccby.glb` | jeremy | **CC-BY 3.0** | https://poly.pizza/m/f8kM9xA_5sV |

The three CC-BY models require attribution; that is what this file and the
in-game credits screen (**C**) provide. The CC0 model carries no attribution
requirement but is credited anyway.

## UI art, font and sound

[Kenney UI Pack 2.0](https://kenney.nl) — **CC0**, credit optional. Full licence
text in `assets/ui/Kenney-License.txt`.

Fonts: Kenney Future and Kenney Future Narrow.

## Engine

[Summer Engine](https://summerengine.com) 0.5.65 (Godot 4.7.2), which loads the
glTF models natively and ships the export templates used to build the game.

Packaged with [Velopack](https://velopack.io) — the same installer and updater
framework Summer Engine itself uses.
