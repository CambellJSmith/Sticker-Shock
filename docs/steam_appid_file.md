# Steam App ID development file

The repository tracks `steam_appid.txt` at the project root with the base launcher App ID `4281680` so Godot editor and local debug runs can initialize Steamworks against the correct application.

The Sticker-Shock DLC App ID remains `4478190`; it is not written to `steam_appid.txt` because the active Steam API session belongs to the launcher application.

`steam_appid.txt` is a local/development identity file. When Steam depot packaging is configured, exclude this file from the shipped depot/build output and let the Steam client provide the application identity for production launches.
