# JUI

A quiet macOS writing pad: a cream sheet, Courier and a ruled page. Needs macOS 26 or later.

## Opening it

JUI isn't notarised, so macOS blocks it the first time. Unzip `JUI.zip`, move `JUI.app` to `/Applications`, then run:

```bash
xattr -cr /Applications/JUI.app
open /Applications/JUI.app
```

To build `JUI.app` and `JUI.zip` yourself, run `./build.sh`.

## License

[MIT](LICENSE)
