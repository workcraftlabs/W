# App icon

`AppIcon.png` is the white-on-black adaptation of the Workcraft Labs handwritten W mark, sourced from the brand's blue-background logo.

`AppIcon.iconset` contains the standard macOS 1× and 2× renditions. Regenerate the packaged icon after updating those images:

```sh
iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
```

`scripts/build-app.sh` installs `AppIcon.icns` into the app bundle; `scripts/Info.plist` declares it as the application icon.
