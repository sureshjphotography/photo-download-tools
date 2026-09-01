# Photo Download Tools

Small helper used by editors working with **SureshJ Photography** to download
a job's files reliably.

It downloads your files, then **checks every single file against the server**
and tells you plainly whether the download is complete. That verification step
is the whole point — a half-finished download that *looks* fine is the problem
this exists to prevent.

- Resumes if it stops. Run it again, it continues.
- Keeps the original folder structure.
- Nothing to install — it fetches what it needs (rclone) on first run.
- Works on macOS, Windows and Linux.

## Getting it

Suresh sends you a link. That page gives you two files:

1. **editor-tools.zip** — the tool (this repo's
   [latest release](../../releases/latest))
2. **config.txt** — yours, with your private download link already in it

Unzip the tool, put `config.txt` in the same folder.

## Using it

### macOS
1. Open `config.txt` in TextEdit. Set `DESTINATION` to where you want the
   files, e.g. `DESTINATION=~/Photos/JobName`. Save.
2. Double-click `DOWNLOAD.command`.

If macOS blocks it: hold Control, click `DOWNLOAD.command`, choose **Open**,
then **Open** again. If that still fails, open Terminal, type `bash` and a
space, drag `DOWNLOAD.command` into the window, press Enter.

### Windows
1. Open `config.txt` in Notepad. Set `DESTINATION`. Save.
2. Double-click `DOWNLOAD.bat`.

Either path style works on either system.

## When it finishes

- **SUCCESS — all files downloaded and verified.** You're done.
- **NOT FINISHED YET** with a count of what's missing. Run it again.

Logs are written to a `logs` folder next to the scripts.

## Notes

- Your link is the only credential. Don't share it; it expires.
- These scripts contain no keys and no client data.
- `config.example.txt` shows the format, but use the `config.txt` from your
  link page — that one has your real link.