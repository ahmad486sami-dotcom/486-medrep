# 486

Personal iPhone app for medical rep field work: voice debriefs, doctor & hospital directory, visit planner with Google Maps routes, coverage map, reminders, PDF sharing and mileage.

## Build the .ipa on GitHub

1. Create a new **private** repository on GitHub.
2. Upload **everything** in this folder, including the hidden `.github` folder.
   - On a Mac, press `Cmd + Shift + .` in Finder to show hidden folders before dragging.
   - If `.github` won't upload: in the repo click **Add file → Create new file**, name it
     `.github/workflows/build-ipa.yml`, and paste the contents of that file.
3. Open the **Actions** tab → **Build 486 IPA** → it runs automatically on every push
   (or press **Run workflow**).
4. When it finishes (about 5–10 min), open the run and download **486-ipa** under *Artifacts*.
   Unzip it to get `486.ipa`.
5. Install with **Sideloadly**, **AltStore**, or your usual signing tool.
   With a free Apple ID the app must be refreshed every 7 days; a paid developer account lasts a year.

If the build fails, download **build-log** from the same run and send the `error:` lines.

## What's inside

| Tab | What it does |
|---|---|
| Today | Progress ring vs. your own target, route button (same-hospital doctors = one stop), timeline, record button, reminders, mileage |
| Map | All hospitals as pins: green visited, orange partly, red not yet, grey away. Filters: period, area, specialty, available now |
| Planner | Week view, add doctors, auto-arrange inside clinic times, warnings for away/out-of-hours/overlaps |
| Directory | Hospitals (phones, location, tips) → doctors (status, clinic times, notes, meeting history) |
| Records | Visit log with search, reminders, stats, mileage (km) |

Plus: Face ID lock, PDF export to share with colleagues (private notes off by default), offline storage, on-device transcription, local notifications.

On iPhones with Apple Intelligence (iOS 26+), debrief summaries are written by the on-device model; otherwise a short summary is taken from the transcript.

## Notes

- All data stays on the phone (SwiftData). Backup/export to iCloud is planned for version 2.
- Record your own debrief after the visit. Don't record doctors without their consent.
- Requires iOS 17 or later.
