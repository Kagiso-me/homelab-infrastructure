
# 06 — Application Configuration
## Tuning Every Service in the Media Stack for Optimal Performance

**Author:** Kagiso Tjeane
**Difficulty:** ?????????? (5/10)
**Guide:** 06 of 06

> Deploying containers is straightforward. Getting them to work *together*, efficiently,
> with correct quality settings, properly wired integrations, and zero manual intervention
> on every download — that is the actual work.
>
> This guide walks through every application in the media stack in the order they must be
> configured. Follow this sequence exactly: Prowlarr first, SABnzbd second, then the *Arrs,
> then Bazarr, Overseerr, Plex, and Navidrome. Dependencies flow downward — configuring
> an application before its dependencies are ready wastes time.

---

# Configuration Order & Dependency Map

```
Prowlarr -----------------------------------------------------------------? (indexers)
    ¦                                                                              ¦
    +-- syncs to --? Sonarr --? SABnzbd --? /mnt/downloads --? /mnt/media/tv     ¦
    +-- syncs to --? Radarr --? SABnzbd --? /mnt/downloads --? /mnt/media/movies ¦
    +-- syncs to --? Lidarr --? SABnzbd --? /mnt/downloads --? /mnt/media/music  ¦
                                                                                   ¦
Bazarr --------------------------------------------------------------------------+
  (reads Sonarr + Radarr libraries, downloads subtitles to /mnt/media)

Overseerr --? Sonarr / Radarr (routes user requests)
           +? Plex (authenticates users, syncs libraries)

Plex --------------------------------------------------------------------------------
  (reads /mnt/media, streams to all clients)

Navidrome ---------------------------------------------------------------------------
  (reads /mnt/media/music, streams via Subsonic API)
```

Configure in this order:

1. Prowlarr
2. SABnzbd
3. Sonarr
4. Radarr
5. Lidarr
6. Bazarr
7. Overseerr
8. Plex
9. Navidrome

---

# 1. Prowlarr — Indexer Hub

**Role:** Central indexer management. Prowlarr holds all your Usenet (and optionally torrent)
indexer credentials and syncs them automatically to Sonarr, Radarr, and Lidarr. None of the
*Arr applications should have indexers configured directly — Prowlarr is the single source of truth.

**Access:** `http://10.0.10.20:9696` or `https://prowlarr.kagiso.me`

---

## 1.1 — First-Time Access

On first visit Prowlarr presents an authentication setup screen. Configure this before doing
anything else — the NPM proxy makes Prowlarr reachable over HTTPS from the LAN.

1. Navigate to **Settings ? General ? Authentication**
2. Set **Authentication Method**: Forms (Login Page)
3. Set a **Username** and **Password**
4. Save and re-login

---

## 1.2 — Add Usenet Indexers

Navigate to **Indexers ? Add Indexer**.

- Search for your Usenet indexer by name
- Fill in credentials: username, password, API key (provider-dependent)
- Enable **Back off on consecutive failures** — prevents your account from being banned
  when a provider has a temporary outage
- Click **Test** — confirm the green checkmark before saving
- Repeat for each indexer

> **Recommended practice:** Add at least two indexers from different providers. If one goes
> down or returns no results, the fallback fires automatically. NZBGeek and Drunken Slug are
> popular complements.

---

## 1.3 — Connect Applications (Settings ? Apps)

Prowlarr pushes its full indexer list to each connected *Arr application via the API.
This must be configured once — after that, adding a new indexer in Prowlarr propagates
to all apps automatically.

Navigate to **Settings ? Apps ? Add Application**.

| Application | Internal URL | Port | API Key Source |
|---|---|---|---|
| Sonarr | `http://sonarr:8989` | 8989 | Sonarr ? Settings ? General ? API Key |
| Radarr | `http://radarr:7878` | 7878 | Radarr ? Settings ? General ? API Key |
| Lidarr | `http://lidarr:8686` | 8686 | Lidarr ? Settings ? General ? API Key |

For each application:

- **Sync Level:** Full Sync — ensures all indexers and any changes propagate automatically
- **Prowlarr Server:** `http://prowlarr:9696` (internal — use container name)
- Click **Test**, then **Save**

> **Why container names?** All services share the `media-net` Docker bridge network.
> Docker's internal DNS resolves `sonarr` to the Sonarr container's IP automatically.
> Never use `10.0.10.20` for inter-container communication — it routes out to the host
> and back in, which breaks if the host IP changes.

---

## 1.4 — Verify Sync Worked

After saving each application connection, Prowlarr triggers an immediate sync.

Verify in each *Arr application:

- **Sonarr:** Settings ? Indexers — should list all Prowlarr-synced indexers with a Prowlarr icon
- **Radarr:** same
- **Lidarr:** same

If indexers do not appear: check that the API key is correct, the Test was green, and the
Prowlarr container can reach the target container by name.

---

## 1.5 — Recommended Settings

| Setting | Location | Recommended Value |
|---|---|---|
| RSS Sync Interval | Settings ? Indexers | 30 minutes |
| Maximum History | Settings ? General | 1000 (default) |
| UI Theme | Settings ? UI | Dark |
| Log Level | Settings ? General | Info (not Debug in production) |

---

# 2. SABnzbd — Usenet Downloader

**Role:** Downloads NZB files from Usenet providers. Receives download jobs from Sonarr,
Radarr, and Lidarr via the API. Organises completed downloads into per-category folders
that the *Arr applications then import.

**Access:** `http://10.0.10.20:8085` or `https://sabnzbd.kagiso.me`

> **Note on port:** The SABnzbd container maps internal port `8080` to host port `8085`
> to avoid conflict with other services. When configuring the *Arr download clients, use
> the internal container port `8080` with hostname `sabnzbd`.

---

## 2.1 — Initial Setup Wizard

On first launch, SABnzbd presents a setup wizard.

**Usenet provider:**

| Field | Value |
|---|---|
| Host | Your provider's hostname (e.g. `news.usenetserver.com`) |
| Port | `563` (SSL) |
| SSL | Enabled |
| Username | Provider account username |
| Password | Provider account password |
| Connections | 8–20 (check your provider's limit per account) |

Click **Test Server** — confirm green before proceeding.

---

## 2.2 — General Settings

Navigate to **Settings ? General**:

| Setting | Value | Reason |
|---|---|---|
| Host | `0.0.0.0` | Accept connections from all interfaces (needed by NPM proxy) |
| Port | `8080` | Internal container port |
| HTTPS | Disabled | NPM handles TLS termination — enabling both causes double-encryption issues |
| API Key | *(auto-generated — note this value)* | Required by Sonarr, Radarr, Lidarr |
| Username / Password | Set these | Secondary auth layer inside NPM-proxied HTTPS |

---

## 2.3 — Categories (Required for *Arr Integration)

The *Arr applications send jobs to SABnzbd with a specific category tag. SABnzbd routes
each download to the matching subfolder. The *Arrs then monitor those subfolders for
completed downloads to import.

Navigate to **Settings ? Categories**:

| Category Name | Folder | Priority |
|---|---|---|
| `tv` | `/downloads/tv` | Default |
| `movies` | `/downloads/movies` | Default |
| `music` | `/downloads/music` | Default |
| `bazarr` | `/downloads/bazarr` | Low |

> These paths are relative to the `/downloads` volume inside the container.
> On the host they resolve to `/mnt/downloads/tv`, `/mnt/downloads/movies`, etc.
> Create the subdirectories on the host if they do not already exist:
>
> ```bash
> mkdir -p /mnt/downloads/{tv,movies,music,bazarr}
> ```

---

## 2.4 — Performance & Speed Settings

Navigate to **Settings ? Switches**:

| Setting | Recommended Value |
|---|---|
| Article cache size | `1024M` (if 4+ GB RAM available; use `256M` if RAM-constrained) |
| Pause if disk free below | `10G` — prevents filling `/mnt/downloads` completely |
| Download limit | Leave at provider's maximum; SABnzbd respects connection limits |
| Post-process only verified jobs | Enabled — avoids importing corrupt downloads |

---

## 2.5 — Retrieve the API Key

**Settings ? General ? API Key** — copy this value.
You will need it when configuring Sonarr, Radarr, and Lidarr download clients.

---

# 3. Sonarr — TV Series Automation

**Role:** Monitors configured TV series, searches for new episodes via Prowlarr, sends NZB
jobs to SABnzbd, then renames and hard-links completed downloads into `/mnt/media/tv`.

**Access:** `http://10.0.10.20:8989` or `https://sonarr.kagiso.me`

---

## 3.1 — Add SABnzbd as Download Client

Navigate to **Settings ? Download Clients ? Add ? SABnzbd**:

| Field | Value |
|---|---|
| Name | SABnzbd |
| Host | `sabnzbd` |
| Port | `8080` |
| API Key | *(from SABnzbd ? Settings ? General)* |
| Category | `tv` |
| Use SSL | Disabled (internal network — no TLS needed) |

Click **Test** — confirm green. Save.

---

## 3.2 — Media Management

Navigate to **Settings ? Media Management**:

**Root Folders:**

- Click **Add Root Folder** ? `/media/tv`

**Renaming — enable these settings:**

| Setting | Value |
|---|---|
| Rename Episodes | Enabled |
| Replace Illegal Characters | Enabled |
| Standard Episode Format | `{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}` |
| Daily Episode Format | `{Series Title} - {Air-Date} - {Episode Title} {Quality Full}` |
| Anime Episode Format | `{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}` |
| Season Folder Format | `Season {season:00}` |
| Multi-Episode Style | Prefixed Range (e.g. `S01E01-E03`) |

**Import settings:**

| Setting | Value |
|---|---|
| Create empty series folders | Disabled — only create folders for content that exists |
| Delete empty folders | Enabled — cleans up after season completes |
| Use Hardlinks instead of Copy | Enabled — avoids duplicating files on disk during import |
| Import Extra Files | Enabled — imports `.srt` subtitle files alongside video |

> **Why hardlinks?** SABnzbd downloads to `/mnt/downloads/tv`. Sonarr needs to "move" the
> file to `/mnt/media/tv`. If both paths are on the same filesystem (TrueNAS NFS mount),
> a hardlink is instant and uses zero extra space. Only enable this when downloads and media
> are on the same volume.

---

## 3.3 — Quality Profiles

Navigate to **Settings ? Quality Profiles ? Add Profile**:

**Profile: HD Only**

| Quality | Enabled | Min Size | Max Size |
|---|---|---|---|
| HDTV-720p | Yes | 200 MB | 4 GB |
| WEB-720p | Yes | 200 MB | 4 GB |
| Bluray-720p | Yes | 200 MB | 4 GB |
| WEB-1080p | Yes | 500 MB | 10 GB |
| Bluray-1080p | Yes | 500 MB | 10 GB |
| HDTV-1080p | Yes | 500 MB | 10 GB |
| CAM | No | — | — |
| HDTV-480p | No | — | — |
| DVD | No | — | — |

**Upgrade Until:** Bluray-1080p — Sonarr will upgrade a WEB-720p episode when a
Bluray-1080p version becomes available.

Set this profile as the **default** for new series.

---

## 3.4 — RSS & Indexer Settings

Navigate to **Settings ? Indexers**:

- After Prowlarr sync, all indexers appear here automatically — no manual entry needed
- **RSS Sync Interval:** 30 minutes (matches Prowlarr)
- **Automatic Search:** Enabled

---

## 3.5 — Notifications (Optional but Recommended)

Navigate to **Settings ? Connect ? Add Connection**:

- **Slack** or **Discord webhook:** sends notifications when an episode is grabbed,
  downloaded, imported, or fails
- Useful for confirming the automation pipeline is working without opening the UI

---

# 4. Radarr — Movie Automation

**Role:** Same lifecycle management as Sonarr, scoped to movies. Monitors your movie
watchlist and library, searches for wanted titles, sends to SABnzbd, imports to `/mnt/media/movies`.

**Access:** `http://10.0.10.20:7878` or `https://radarr.kagiso.me`

---

## 4.1 — Add SABnzbd as Download Client

Navigate to **Settings ? Download Clients ? Add ? SABnzbd**:

| Field | Value |
|---|---|
| Name | SABnzbd |
| Host | `sabnzbd` |
| Port | `8080` |
| API Key | *(from SABnzbd)* |
| Category | `movies` |

Test and save.

---

## 4.2 — Media Management

Navigate to **Settings ? Media Management**:

**Root Folders:** `/media/movies`

**Naming:**

| Setting | Value |
|---|---|
| Rename Movies | Enabled |
| Replace Illegal Characters | Enabled |
| Movie Folder Format | `{Movie Title} ({Release Year}) {tmdb-{TmdbId}}` |
| Standard Movie Format | `{Movie Title} ({Release Year}) - {Quality Full}` |
| Use Hardlinks | Enabled |
| Import Extra Files | Enabled |

---

## 4.3 — Quality Profiles

**Profile: HD Only** (same logic as Sonarr):

- Enable: WEB-720p, WEB-1080p, Bluray-720p, Bluray-1080p
- Disable: CAM, HDTV-480p, DVD
- **Upgrade Until:** Bluray-1080p

**Custom Formats (optional):**

Navigate to **Settings ? Custom Formats ? Add**:

- `x265` preferred — x265-encoded releases are significantly smaller than x264 at
  equivalent quality. Useful if storage capacity is a constraint.
- `Remux` preferred over Bluray encode if you want bit-perfect source quality.

---

## 4.4 — Import Lists (Optional)

Navigate to **Settings ? Import Lists ? Add**:

- **Trakt.tv lists** — automatically add movies from your Trakt watchlist, trending
  lists, or custom collections as wanted titles in Radarr
- **IMDb lists** — same capability via IMDb public lists
- Set **Quality Profile** and **Root Folder** to match your standards

---

# 5. Lidarr — Music Automation

**Role:** Artist and album lifecycle management. Monitors configured artists, searches for
new releases via Prowlarr, downloads via SABnzbd, and imports to `/mnt/media/music`.

**Access:** `http://10.0.10.20:8686` or `https://lidarr.kagiso.me`

---

## 5.1 — Add SABnzbd as Download Client

Navigate to **Settings ? Download Clients ? Add ? SABnzbd**:

| Field | Value |
|---|---|
| Name | SABnzbd |
| Host | `sabnzbd` |
| Port | `8080` |
| API Key | *(from SABnzbd)* |
| Category | `music` |

Test and save.

---

## 5.2 — Media Management

Navigate to **Settings ? Media Management**:

**Root Folders:** `/media/music`

**Naming:**

| Setting | Value |
|---|---|
| Rename Tracks | Enabled |
| Replace Illegal Characters | Enabled |
| Artist Folder Format | `{Artist Name}` |
| Album Folder Format | `{Album Title} ({Release Year})` |
| Multi-Disc Track Format | `{Medium Format} {medium:00}/{track:00} - {Track Title}` |
| Standard Track Format | `{track:00} - {Track Title}` |
| Use Hardlinks | Enabled |

---

## 5.3 — Quality Profiles

Navigate to **Settings ? Quality Profiles ? Add Profile**:

**Profile: Lossless Preferred**

| Quality | Enabled | Priority |
|---|---|---|
| FLAC | Yes | Highest |
| MP3-320 | Yes | Second |
| MP3-256 | Yes | Third |
| MP3-192 | No | — |
| MP3-128 | No | — |

If storage is constrained, use **MP3-320 as maximum** — a single FLAC album can be
600 MB–2 GB while MP3-320 is typically 100–300 MB.

---

## 5.4 — Metadata & Tags

Navigate to **Settings ? Metadata**:

- **Write metadata tags to audio files:** Enabled
- Embeds artist, album, track number, year, and artwork directly in the audio file.
  Navidrome and mobile players read these embedded tags — library accuracy improves significantly.

---

## 5.5 — Navidrome Integration

After a Lidarr import, Navidrome needs to rescan its library to pick up new music.
Lidarr can trigger this automatically.

Navigate to **Settings ? Connect ? Add Connection ? Custom Script** (or Webhook):

- **On Import:** trigger a Navidrome library scan
- Navidrome exposes a scan endpoint at `http://navidrome:4533/rest/startScan`
  using the Subsonic API — use the admin credentials

Alternatively, Navidrome scans on a schedule (`ND_SCANSCHEDULE=1h` in the compose file)
so new music appears within the hour even without an explicit trigger.

---

# 6. Bazarr — Subtitle Automation

**Role:** Monitors Sonarr and Radarr libraries, automatically searches subtitle providers
for matching subtitles, and saves them alongside the media files. Subtitles appear in Plex
automatically once downloaded.

**Access:** `http://10.0.10.20:6767` or `https://bazarr.kagiso.me`

---

## 6.1 — Connect to Sonarr

Navigate to **Settings ? Sonarr**:

| Field | Value |
|---|---|
| Enabled | Yes |
| Host | `sonarr` |
| Port | `8989` |
| API Key | *(Sonarr ? Settings ? General ? API Key)* |
| Base URL | *(leave empty)* |
| SSL | Disabled |

Click **Test** — confirm green. Save.

---

## 6.2 — Connect to Radarr

Navigate to **Settings ? Radarr**:

| Field | Value |
|---|---|
| Enabled | Yes |
| Host | `radarr` |
| Port | `7878` |
| API Key | *(Radarr ? Settings ? General ? API Key)* |
| Base URL | *(leave empty)* |
| SSL | Disabled |

Test and save.

---

## 6.3 — Configure Subtitle Providers

Navigate to **Settings ? Providers ? Add Provider**:

**OpenSubtitles.com** (primary — largest database):

| Field | Value |
|---|---|
| Username | Your opensubtitles.com account |
| Password | Your password |
| Use anti-flood system | Enabled |
| Maximum simultaneous downloads | 5 |

> Register at [opensubtitles.com](https://opensubtitles.com) — the free tier allows
> 20 subtitle downloads per day. Bazarr's anti-flood system respects this limit automatically.

**Subscene** (secondary provider):

- Add as a fallback — Subscene has strong coverage for non-English content and
  older titles not yet on OpenSubtitles

**Addic7ed** (optional — excellent for current US/UK TV):

- Requires a free account at addic7ed.com
- Best for freshly-aired TV episodes where other providers may lag

---

## 6.4 — Language Settings

Navigate to **Settings ? Languages**:

**Create a Language Profile:**

- **Profile Name:** English
- **Languages:** English (required)
- **Cutoff:** English — Bazarr will not download a lower-priority language if English is available

Navigate to **Settings ? Languages ? Default Settings**:

- **Series default profile:** English
- **Movies default profile:** English

---

## 6.5 — Score Thresholds

Navigate to **Settings ? Subtitles**:

Subtitle providers assign a match score (0–100%) based on how closely the subtitle matches
the specific video file (resolution, release group, encoding). A low-score subtitle is usually
out of sync or for a different cut.

| Setting | Recommended Value | Reasoning |
|---|---|---|
| Minimum score for movies | 80 | Movies have fewer variants — 80% is achievable |
| Minimum score for TV episodes | 60 | TV has many release groups — 60% prevents rejecting valid subs |
| Cutoff score (do not upgrade above) | 90 | At 90%+ the sub is effectively perfect — no upgrade needed |

---

## 6.6 — Post-Processing

Navigate to **Settings ? Subtitles ? Post-processing**:

| Setting | Value |
|---|---|
| Encode subtitles to UTF-8 after download | Enabled — prevents encoding issues in Plex |
| Hearing-impaired subtitles | Download if regular not found (optional) |

---

# 7. Overseerr — Media Request Portal

**Role:** User-facing web portal for requesting new movies and TV series. Authenticated users
browse and submit requests; Overseerr routes them to Radarr (movies) or Sonarr (TV). Removes
the need to give family and friends direct access to the *Arr interfaces.

**Access:** `http://10.0.10.20:5055` or `https://requests.kagiso.me`

---

## 7.1 — Initial Setup Wizard

On first visit, Overseerr launches a setup wizard. Complete it in full — skipping steps
causes authentication issues later.

**Step 1 — Sign in with Plex:**

Click **Sign in with Plex** and authenticate with your Plex account. This links Overseerr
to your Plex identity and allows it to import your Plex users.

**Step 2 — Configure Plex Connection:**

| Field | Value |
|---|---|
| Plex URL | `http://plex:32400` |
| Plex Token | See below |

**Retrieving your Plex Token:**

Option A — Extract from Plex preferences file:

```bash
grep -o 'PlexOnlineToken="[^"]*"' \
  /srv/docker/appdata/plex/Library/Application\ Support/Plex\ Media\ Server/Preferences.xml
```

Option B — Browser method:

1. Sign in at [plex.tv](https://app.plex.tv)
2. Open any library item
3. Click the `...` menu ? **Get Info** ? **View XML**
4. Copy the `X-Plex-Token` value from the URL in your browser

**Step 3 — Sync Libraries:**

Overseerr scans your Plex libraries to know what media you already own. Click **Sync Libraries**
and select Movies, TV Shows, and Music. This prevents users from requesting content already
in your library.

**Step 4 — Invite Users:**

Navigate to **Settings ? Users ? Import Plex Users** — imports all users with access to
your Plex server so they can log in to Overseerr with their Plex credentials.

---

## 7.2 — Configure Sonarr

Navigate to **Settings ? Services ? Sonarr ? Add Server**:

| Field | Value |
|---|---|
| Default Server | Yes |
| Server Name | Production Sonarr |
| Host | `sonarr` |
| Port | `8989` |
| API Key | *(Sonarr ? Settings ? General)* |
| SSL | Disabled |
| Quality Profile | HD Only *(or whichever profile you created in Sonarr)* |
| Root Folder | `/media/tv` |
| Language Profile | English |
| Season Folders | Enabled |

Test and save.

---

## 7.3 — Configure Radarr

Navigate to **Settings ? Services ? Radarr ? Add Server**:

| Field | Value |
|---|---|
| Default Server | Yes |
| Server Name | Production Radarr |
| Host | `radarr` |
| Port | `7878` |
| API Key | *(Radarr ? Settings ? General)* |
| SSL | Disabled |
| Quality Profile | HD Only |
| Root Folder | `/media/movies` |

Test and save.

---

## 7.4 — General Settings

Navigate to **Settings ? General**:

| Setting | Value |
|---|---|
| Application URL | `https://requests.kagiso.me` |
| Hide Available Media | Disabled — users can still see what you have |
| Allow Partial Series Requests | Enabled — users can request specific seasons |
| Automatic Approval | Enabled for trusted users; manual review for guests |

---

## 7.5 — User Permissions

Navigate to **Settings ? Users**:

Set default permissions for imported Plex users:

| Permission | Default |
|---|---|
| Request Movies | Enabled |
| Request TV Series | Enabled |
| Auto-approve own requests | Disabled (requires admin approval) |
| Advanced requests | Disabled (cannot override quality profiles) |

For trusted users (family), enable **Auto-approve** individually.

---

## 7.6 — Notifications

Navigate to **Settings ? Notifications ? Slack** (or Discord):

Configure a webhook to receive notifications when:

- A request is submitted
- A request is approved or declined
- A request completes (media appears in Plex)

This closes the feedback loop for users who submit a request and want to know when it is ready.

---

# 8. Plex — Media Server

**Role:** Streams video, audio, and photos to any client — web browser, Plex app on TV,
iOS, Android, Chromecast, Roku, Apple TV. Transcodes on-the-fly when the client cannot
direct-play the source format.

**Access:** `http://10.0.10.20:32400/web` or `https://plex.kagiso.me`

---

## 8.1 — Initial Setup

On first visit, Plex launches a setup wizard to claim the server to your Plex account.

1. Sign in with your Plex account (or create one at plex.tv)
2. Give the server a name: `homelab` or your preferred name
3. Add libraries (see section 8.2)
4. Allow the initial scan to complete

---

## 8.2 — Library Setup

Navigate to **Settings ? Libraries ? Add Library**:

| Library Name | Path | Type |
|---|---|---|
| Movies | `/media/movies` | Movies |
| TV Shows | `/media/tv` | TV Shows |
| Music | `/media/music` | Music |

For each library, Plex automatically scans the folder and matches files against The Movie
Database (TMDB) and TheTVDB to pull in metadata, posters, and descriptions.

> The `/media` path inside the container maps to `/mnt/media` on the host (NFS mount from
> TrueNAS). Plex must have read access to this mount — confirm the PUID/PGID in the compose
> file matches the NFS share ownership.

---

## 8.3 — Hardware Transcoding

Plex transcodes video when a client cannot direct-play the source file (wrong codec, bitrate
too high for the connection, or subtitle burn-in required). Hardware transcoding offloads
this from the CPU to the NUC's integrated GPU, allowing multiple simultaneous streams.

> **Prerequisite:** Hardware transcoding requires `/dev/dri` to exist inside the docker-vm.
> This is only possible after configuring Intel GVT-g on the Proxmox host — complete the
> **iGPU Passthrough appendix in Guide 04** before enabling these settings.

**Requirements:** Plex Pass subscription (required for hardware transcoding)

Navigate to **Settings ? Transcoder**:

| Setting | Value |
|---|---|
| Use hardware acceleration when available | Enabled |
| Use hardware-accelerated video encoding | Enabled |
| Use hardware-accelerated video decoding | Enabled |
| Maximum simultaneous video transcode | Unlimited (or 4 if you want a hard cap) |
| Background transcoding x264 preset | Fast — balances quality and CPU usage |

**Verify hardware transcoding is active:**

1. Start playback of a video on a client that requires transcoding (e.g., a phone on a
   slow connection)
2. Navigate to **Settings ? Troubleshooting ? Dashboard** (or the Plex web dashboard)
3. The active stream should show `(hw)` next to the video codec — e.g., `H.264 (hw)`

If `(hw)` does not appear, confirm the `/dev/dri` device is mounted in the container:

```bash
docker exec plex ls /dev/dri/
# Expected: card0  renderD128
```

If the device exists but transcoding still falls back to software, add the `docker` user
to the `render` and `video` groups:

```bash
sudo usermod -aG render,video docker
# Recreate the Plex container to pick up the new group membership:
docker compose -f /srv/docker/stacks/media-stack.yml up -d --force-recreate plex
```

---

## 8.4 — Network Settings

Navigate to **Settings ? Remote Access**:

- **Enable Remote Access:** Disabled — this homelab uses Tailscale for remote access,
  not Plex Relay servers. Disabling prevents bandwidth routing through Plex's infrastructure.

Navigate to **Settings ? Network**:

| Setting | Value |
|---|---|
| LAN Networks | `10.0.10.0/24` — mark as local network |
| Treat WAN IP as LAN bandwidth | Disabled |
| Enable Relay | Disabled |

Marking `10.0.10.0/24` as a LAN network tells Plex not to apply remote stream quality
limits for clients on the local network. This allows full-quality direct play.

---

## 8.5 — Library Scan Schedule

Navigate to **Settings ? Troubleshooting ? Scheduled Tasks**:

Plex scans libraries on a schedule to detect new content imported by Sonarr and Radarr.

| Task | Recommended Schedule |
|---|---|
| Update all libraries | Every 6 hours |
| Empty trash automatically after every scan | Enabled |
| Allow media deletion | Enabled (allows Sonarr/Radarr to remove files via Plex) |
| Generate chapter images | Enabled (improves scrubbing previews) |

> Sonarr and Radarr send a scan trigger to Plex via the **Connect** webhook immediately
> after importing a file — the 6-hour schedule is a safety net, not the primary mechanism.
> Configure the webhook in Sonarr and Radarr under **Settings ? Connect ? Plex Media Server**.

---

## 8.6 — Plex Notifications (Settings ? Connect in Sonarr/Radarr)

To trigger immediate Plex library scans after imports:

**In Sonarr:** Settings ? Connect ? Add ? Plex Media Server

| Field | Value |
|---|---|
| Host | `plex` |
| Port | `32400` |
| Plex Token | *(extracted in Overseerr setup — section 7.1)* |
| On Import | Enabled |
| On Upgrade | Enabled |

Repeat in Radarr for movie imports.

---

# 9. Navidrome — Music Streaming

**Role:** Self-hosted music streaming server with a Subsonic-compatible API. Streams your
music library to any Subsonic-compatible mobile app, the Navidrome web UI, or third-party
players. Complements Plex for music — Navidrome has richer music-specific features including
scrobbling, playlists, and Subsonic API support.

**Access:** `http://10.0.10.20:4533` or `https://music.kagiso.me`

---

## 9.1 — First-Time Setup

Navigate to `http://10.0.10.20:4533`. On first visit, Navidrome presents an admin account
creation form. This is the only account that can manage the server — create it carefully.

| Field | Value |
|---|---|
| Username | `admin` (or your preferred admin name) |
| Password | Strong password — this account has full control |

After creating the admin account, Navidrome immediately scans the music library at `/music`
(mapped from `/mnt/media/music` in the compose file). The initial scan duration depends on
library size — a 50,000-track library may take 10–20 minutes.

Monitor scan progress at the bottom of the Navidrome UI — a scan indicator shows active
indexing. Navidrome reads embedded ID3/FLAC tags from each file. If tags are incomplete,
metadata will be sparse — this is why Lidarr's tag writing (section 5.4) matters.

---

## 9.2 — Library Settings

Navigate to **Settings ? Personal** (per-user) or configure via environment variables
in the compose file (server-wide defaults):

| Environment Variable | Value | Purpose |
|---|---|---|
| `ND_SCANSCHEDULE` | `1h` | Automatically rescan every hour — picks up Lidarr imports |
| `ND_LOGLEVEL` | `info` | Sufficient for production; use `debug` only when troubleshooting |
| `ND_SESSIONTIMEOUT` | `24h` | Users stay logged in for 24 hours |
| `ND_BASEURL` | *(empty)* | Leave empty unless running behind a subpath (e.g. `/music`) |

These are set in the compose file — they do not require UI configuration.

---

## 9.3 — Last.fm Scrobbling

Navidrome supports scrobbling plays to Last.fm for listening history and music discovery.
Configuration is per-user.

Navigate to **Settings ? Personal ? Last.fm**:

1. Click **Link Last.fm account**
2. Authenticate with your Last.fm credentials
3. Enable scrobbling

Server-level Last.fm API credentials (required for artist biography and artist image
lookup) are set via environment variables in the compose file:

```yaml
environment:
  - ND_LASTFM_ENABLED=true
  - ND_LASTFM_APIKEY=your_api_key
  - ND_LASTFM_SECRET=your_secret
```

Obtain a free API key at [last.fm/api](https://www.last.fm/api/account/create).

---

## 9.4 — Mobile Client Setup

Navidrome implements the full Subsonic API — any Subsonic-compatible mobile app works.

**Recommended clients:**

| Platform | Client | Notes |
|---|---|---|
| Android | Symfonium | Best UI, offline sync, gapless playback — paid |
| Android | Ultrasonic | Free, open source, solid feature set |
| iOS | Amperfy | Free, open source, excellent Subsonic support |
| iOS | Substreamer | Paid — polished UI, offline support |
| Desktop | Sublime Music | Linux/macOS — GTK3, Subsonic-native |

**Connection settings for any Subsonic client:**

| Field | Value |
|---|---|
| Server URL | `https://music.kagiso.me` |
| API type | Subsonic |
| Username | Your Navidrome username |
| Password | Your Navidrome password |
| API version | Leave as auto-detect |

---

# Verification — All Integrations Working

After completing all nine sections, run this verification sequence to confirm the full
pipeline is operational end to end.

## Container Health

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

All containers must show `(healthy)`. Any container stuck in `(health: starting)` after
5 minutes indicates a misconfiguration — check logs with `docker logs <container_name>`.

## Inter-Container Connectivity

```bash
# Sonarr can reach SABnzbd
docker exec sonarr curl -sf http://sabnzbd:8080/sabnzbd/api?mode=version

# Radarr can reach Prowlarr
docker exec radarr curl -sf http://prowlarr:9696/ping

# Bazarr can reach Sonarr
docker exec bazarr curl -sf http://sonarr:8989/ping

# Overseerr can reach Radarr
docker exec overseerr curl -sf http://radarr:7878/ping
```

All four commands should return a non-empty response. A `curl: (6) Could not resolve host`
error means the container is not on `media-net` — inspect with `docker inspect <name>`.

## Prowlarr Sync Verification

```bash
# Prowlarr should list its connected applications
curl -s -H "X-Api-Key: <prowlarr_api_key>" \
  http://10.0.10.20:9696/api/v1/applications | python3 -m json.tool | grep -E "name|syncLevel"
```

Expected output — three entries (Sonarr, Radarr, Lidarr) each with `"syncLevel": "fullSync"`.

## SABnzbd End-to-End Test

1. Navigate to `http://10.0.10.20:8085`
2. **Queue ? Manual NZB** — upload a small test NZB file (any free Usenet test NZB)
3. Confirm SABnzbd connects to the provider, downloads, and reports complete
4. Check `/mnt/downloads/` for the completed file

## Bazarr Provider Status

Navigate to `http://10.0.10.20:6767` ? **Settings ? Providers**:

Each enabled provider should show a green status indicator. A red indicator means
authentication failed or the provider is rate-limiting — check credentials.

## Plex Hardware Transcoding Test

1. On a mobile phone, open the Plex app and connect to your server
2. Set quality to **Original** — this forces direct play for a compatible file
3. Set quality to **720p 4 Mbps** — for a 1080p source, Plex must transcode
4. Open the Plex dashboard during playback — confirm `(hw)` next to the video stream

## Navidrome Library Scan Status

Navigate to `http://10.0.10.20:4533`:

- The music library should display your artists and albums from `/mnt/media/music`
- If the library is empty, check that `/mnt/media/music` contains music files and
  that the volume mount is correct: `docker exec navidrome ls /music`

---

# Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Prowlarr indexers not appearing in Sonarr | API key wrong or Prowlarr cannot reach Sonarr | Re-test the application connection in Prowlarr ? Settings ? Apps |
| SABnzbd download stuck at 0 B/s | Usenet provider SSL connection refused | Verify port (563), SSL enabled, and credentials in SABnzbd Settings ? Servers |
| Sonarr "No files found" after SABnzbd completes | Category mismatch | Confirm Sonarr download client category is `tv` and SABnzbd `tv` category folder is `/downloads/tv` |
| Radarr imports to wrong folder | Root folder misconfigured | Settings ? Media Management ? Root Folders — verify `/media/movies` exists |
| Bazarr downloads subtitles with wrong encoding | Post-processing not enabled | Settings ? Subtitles ? enable "Encode to UTF-8 after download" |
| Overseerr "Cannot connect to Plex" | Plex token expired or incorrect | Re-extract the token from Preferences.xml; regenerate in plex.tv if necessary |
| Plex transcoding shows `(cpu)` instead of `(hw)` | `/dev/dri` not mounted or permissions issue | Confirm `/dev/dri` in container; add user to `render` group and recreate container |
| Navidrome library empty after scan | Volume mount wrong or music path incorrect | `docker exec navidrome ls /music` — should list your music folders |
| Navidrome shows tracks but no metadata | Audio files missing embedded tags | Ensure Lidarr tag writing is enabled; re-tag files with beets or MusicBrainz Picard |
| Container shows `(unhealthy)` | Startup failure or misconfiguration | `docker logs <container_name> --tail 50` — look for the first ERROR line |

---

# Exit Criteria

This guide is complete when every item below is confirmed:

```
? Prowlarr has at least one indexer configured, tested (green), and synced to all three *Arrs
? SABnzbd connected to Usenet provider — test download completes successfully
? SABnzbd categories configured: tv, movies, music, bazarr
? Sonarr connected to SABnzbd (category: tv) and Prowlarr indexers visible
? Radarr connected to SABnzbd (category: movies) and Prowlarr indexers visible
? Lidarr connected to SABnzbd (category: music) and Prowlarr indexers visible
? Bazarr connected to Sonarr and Radarr — both show green status
? Bazarr has at least one subtitle provider configured with green status
? Overseerr signed in with Plex, Sonarr and Radarr connected, libraries synced
? Plex libraries created for Movies, TV Shows, Music — initial scan complete
? Plex hardware transcoding confirmed active via dashboard (hw) indicator
? Navidrome library populated — artists and albums visible in UI
? All containers healthy: docker ps shows (healthy) for every service
```

Once all items are confirmed, the media automation pipeline is fully operational. New content
requested through Overseerr flows to Sonarr or Radarr ? Prowlarr ? SABnzbd ? import ? Plex
library ? Bazarr subtitles — without any manual intervention.

---

## Navigation

| | Guide |
|---|---|
| ? Previous | [05 — Monitoring & Logging](./04_monitoring_and_logging.md) |
| Current | **06 — Application Configuration** |
| ? Next | *End of series* |
