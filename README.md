# Too Busy To Click

The Omarchy bar, but panels open on hover. Move to the next icon to switch, move away to close.
Clicks and shortcuts work as usual.

## Install

    omarchy plugin add https://github.com/zacksolver/too-busy-to-click.git
    omarchy plugin enable zacksolver.too-busy-to-click

Back to the stock bar:

    omarchy plugin enable omarchy.bar

## Settings

Optional, in `~/.config/omarchy/shell.json`:

```json
"bar": {
  "hover": { "enabled": true, "openDelay": 150, "closeDelay": 300 }
}
```

Delays are in ms.

## Omarchy updates

Run `./sync-upstream.sh` to pull in the latest stock bar, then `omarchy restart shell`.
