<div align="center">

# altv_ox_props

**Per-set, in-game prop placement & marking for FiveM, powered by the Ox ecosystem**

Place and organise GTA V props directly in‑world with a gizmo editor. Group props
into named **sets**, stream them by distance, and persist them to the database so
your work survives a restart.

[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Game](https://img.shields.io/badge/FiveM-blueviolet)
![Lua](https://img.shields.io/badge/Lua-5.4-00007c)

</div>

---

## ✨ Features

- **In‑game gizmo editor** — translate, rotate and snap props using a classic 3‑view gizmo, with free‑cam and cursor modes.
- **Set‑based organisation** — group props into named sets, toggle whole sets on/off, rename or delete them.
- **Distance streaming** — props spawn/despawn around the player (or the editor camera) for consistent performance.
- **Optional persistence** — persist props and sets to MySQL via `oxmysql` when `config.persist = true`.
- **Server‑authoritative** — every mutation is validated and permission‑checked server‑side.

## 🔧 Dependencies

| Dependency | Required | Purpose |
| --- | --- | --- |
| [ox_lib](https://github.com/overextended/ox_lib) | ✅ Always | UI, locale, callbacks, addon library |
| [oxmysql](https://github.com/overextended/oxmysql) | Only when persisting | Database storage when `config.persist = true` |

## 📦 Installation

1. Clone or copy the folder into your `resources` directory and name it `altv_ox_props`.
2. Ensure `ox_lib` is started before it in `server.cfg`:

```cfg
ensure ox_lib
ensure altv_ox_props
```

3. *(Optional)* To enable persistence, run the schema in [`sql/install.sql`](sql/install.sql) and set `config.persist = true`.

## 🎮 Usage

Run `/props` (default ace: `admin`) to open the editor. The command first shows the
**Set** menu — pick the set new props are placed into, then press **E** to open the
props menu.

### Controls

| Mode | Key | Action |
| --- | --- | --- |
| Freecam | `W A S D` | Move camera |
| Freecam | `Space` / `LCtrl` | Up / Down |
| Freecam | Mouse wheel | Adjust speed |
| Freecam | `LALT` | Toggle cursor mode |
| Freecam | `E` | Open props menu |
| Freecam | `BACKSPACE` | Exit editor |
| Cursor | `T` / `R` | Translation / rotation gizmo |
| Cursor | `L` | Toggle world / local space |
| Cursor | `G` | Snap to ground |
| Cursor | `ENTER` | Confirm placement |
| Cursor | `DEL` | Delete selected prop |
| Cursor | `LALT` | Back to freecam |

### Adding a prop

1. Run `/props`, select a set, then press **E**.
2. Choose **Add Prop** to open the searchable catalog.
3. Select a model and press **Place**, or choose **Custom Model** to enter a model name (e.g. `prop_bin_05a`).
4. Position with the gizmo, then press **ENTER**.

Model names are validated against the game's model list before spawning.

## ⚙️ Configuration

See [`config.lua`](config.lua).

| Option | Default | Description |
| --- | --- | --- |
| `command` | `props` | Chat command that opens the editor |
| `permission` | `admin` | Ace permission required to use the editor |
| `maxProps` | `500` | Maximum number of props |
| `renderDistance` | `150.0` | Distance within which props spawn |
| `spawnDelay` | `200` | Milliseconds between spawn batches |
| `gizmoMaxDistance` | `50.0` | Max distance a prop can be moved from its grab origin |
| `persist` | `false` | Persist props/sets to the database and restore after restart |
| `preview` | disabled | Optional catalog thumbnail/mesh preview and Forge URL integration |

`permission` may be an ace (e.g. `admin`) or a principal (e.g. `group.admin`),
resolved through the player's identifiers.

## 🔒 Security

All prop mutations are validated server-side. The server rejects:

- Requests without the configured ace permission
- Model names that are not alphanumeric/underscore, or longer than 64 characters
- Coordinates outside the GTA V map bounds
- Non‑finite numbers (`NaN`, `inf`)

## 📁 Structure

```
altv_ox_props
├── client/          # Streaming, gizmo editor, context menus, catalog bridge, DataView
├── data/             # Browsable prop catalog
├── locales/         # ox_lib locale files
├── server/          # Storage (oxmysql), validation, main logic
├── sql/             # Persistent schema (install.sql)
├── web/              # Catalog NUI
├── config.lua       # Resource configuration
└── fxmanifest.lua   # FiveM resource manifest
```

## 📄 License

Released under the [MIT License](LICENSE). Copyright © 2026 Ethan Kerdelhue.

The gizmo implementation is adapted from [`qbx_properties`](https://github.com/Qbox-project/qbx_properties).
