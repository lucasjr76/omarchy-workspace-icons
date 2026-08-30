# Workspace Icons

![Workspace Icons in the Omarchy bar: workspace 1 holds Brave and a terminal, the focused workspace 2 holds Firefox and a settings app in full colour, workspaces 3 to 5 are empty](preview.png)

An Omarchy shell bar widget that pairs each workspace **number** with the
**icons of the apps open on that workspace**, grouped so the eye can tell which
icons belong to which number.

The default layout puts the icons next to the number, with a wide gap between
workspaces and a narrow one between the icons inside a workspace. Icons are
desaturated everywhere except on the focused workspace, so colour marks where
you are. An `overlay` layout that draws the icons on top of the number is also
available, but two marks competing for one 26px cell is hard to read — it is
kept as an option, not the default.

It is a drop-in alternative to the built-in `omarchy.workspaces` widget: same
click-to-focus behaviour, plus scroll-to-switch and a tooltip listing the apps.

## Requirements

Omarchy 4 or newer, which is where the bar became a Quickshell shell with
plugin support. No dependency beyond what Omarchy already ships: the widget
uses `Quickshell.Hyprland` for workspace state, `QtQuick.Effects` for the
grayscale pass, and the shell's own icon index to resolve app icons.

## Install

```bash
omarchy plugin add https://github.com/lucasjr76/omarchy-workspace-icons.git --enable
omarchy plugin disable omarchy.workspaces   # optional: replace the stock one
```

## Uninstall

```bash
omarchy plugin remove lucasjr76.workspace-icons
omarchy plugin enable omarchy.workspaces     # if you had disabled the stock one
```

Removal takes the widget out of `~/.config/omarchy/shell.json` and deletes
`~/.config/omarchy/plugins/lucasjr76.workspace-icons/`. Nothing is written
anywhere else.

## License

MIT — see [LICENSE](LICENSE).

## Settings

Set them inline on the widget's entry in `~/.config/omarchy/shell.json`
(hot-reloads on save) or from Setup > Plugins.

| Key | Default | What it does |
|---|---|---|
| `layout` | `beside` | `beside` = number then icons. `overlay` = icons drawn on top of the number |
| `minWorkspaces` | `5` | Workspaces always shown, even when empty |
| `groupSpacing` | `10` | Gap between workspaces, in px. Keep it clearly wider than the gap between icons |
| `maxIcons` | `3` | Icons drawn per workspace (distinct apps, in stacking order) |
| `iconSize` | `15` | Icon size in px |
| `iconOpacity` | `100` | Icon opacity on the focused workspace (%) |
| `inactiveIconOpacity` | `80` | Icon opacity on the other workspaces (%) |
| `iconGrayscale` | `inactive` | `inactive` = colour only where you are, `always` = never colour, `never` = always colour |
| `showNumber` | `always` | `empty-only` hides the number once a workspace has apps |
| `numberScale` | `125` | Number size, as a % of the bar font size |
| `numberOpacityOccupied` | `100` | Number opacity when the workspace has apps (%) |
| `numberOpacityEmpty` | `45` | Number opacity when the workspace is empty (%) |
| `numberBold` | `true` | Draw the number bold |
| `unknownIcons` | `generic` | `generic` = placeholder icon for apps with no desktop entry, `hide` = number only |
| `hideEmpty` | `false` | Hide empty workspaces past `minWorkspaces` |
| `scrollToSwitch` | `true` | Scroll over the widget to move between workspaces |

## How icons are resolved

The window's Wayland `appId` (Hyprland's window `class`) is matched against the
desktop-entry database — `heuristicLookup`, then exact id, then a scan of
`StartupWMClass` — and the entry's `Icon=` is resolved through the shell's own
icon index. Apps with no desktop entry fall back to the app id used as an icon
name, then to a generic placeholder.
