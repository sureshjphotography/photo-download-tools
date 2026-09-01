# Photo Download Tools

Small helper used by editors working with **SureshJ Photography** to download
a job's RAW files reliably.

It downloads your files, then **checks every single file against the server**
and tells you plainly whether the download is complete. That verification step
is the whole point — a half-finished download that *looks* fine is the problem
this exists to prevent.

- Resumes if it stops. Run it again, it picks up where it left off.
- Keeps the original folder structure.
- Nothing to install — it fetches what it needs (rclone) on first run.
- Works on macOS, Windows and Linux.

## Getting it

Download **editor-tools.zip** from the
[latest release](../../releases/latest), or use the link Suresh sent you.

You also need a **config.txt** containing your private job link — Suresh
provides that. Put it next to the scripts.

## Using it

### macOS
1. Open `config.txt` in TextEdit. Set `DESTINATION` to where you want the
   photos, e.g. `DESTINATION=~/Photos/JobName`. Save.
2. Double-click `DOWNLOAD.command`.

If macOS blocks it: right-click `DOWNLOAD.command` → **Open** → **Open**.
If that still fails, open Terminal, type `bash` and a space, drag
`DOWNLOAD.command` into the window, press Enter.

### Windows
1. Open `config.txt` in Notepad. Set `DESTINATION`. Save.
2. Double-click `DOWNLOAD.bat`.

## When it finishes

You get one of two results:

- **SUCCESS — all files downloaded and verified.** You're done.
- **NOT FINISHED YET** with a count of what's missing. Run it again.

Logs are written to a `logs` folder next to the scripts.

## Notes

- Your link is the only credential. Don't share it; it expires.
- These scripts contain no keys and no client data.