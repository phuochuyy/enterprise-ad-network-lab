# Working agreement

Even as a one-person lab, changes follow the same flow a team would use.

## Branches

`main` is protected: no direct pushes, PR + green CI required.

| Prefix | Use |
| --- | --- |
| `feat/` | new capability (`feat/opnsense-vlan-segmentation`) |
| `fix/` | correct broken behaviour |
| `docs/` | documentation only |
| `chore/` / `ci/` | tooling, repo hygiene, pipelines |

## Commits — [Conventional Commits](https://www.conventionalcommits.org/)

```text
<type>(<scope>): <imperative summary, <= 72 chars>

<body: what and why, wrapped at 72>

Refs: #<issue>
```

Scopes: `iac`, `packer`, `network`, `vpn`, `ad`, `dhcp`, `fs`, `gpo`, `linux`, `docs`, `media`, `ci`.

## Pull requests

- One issue per PR, `Closes #n` in the description.
- Evidence (screenshot, GIF, command output) attached for anything that touches the lab.
- Squash-merge; the PR title becomes the commit on `main`.

## Releases

SemVer tags at the end of each milestone, `CHANGELOG.md` updated, MP4 recordings attached as release assets.

## Evidence capture

```bash
scripts/media/shot.sh dc01-dcdiag              # active window -> docs/media/NN-dc01-dcdiag.png
scripts/media/rec.sh start dhcp-failover       # ... perform the demo ...
scripts/media/rec.sh stop                      # -> NN-dhcp-failover.mp4 + .gif
scripts/media/cast.sh tf-apply -- terraform -chdir=terraform apply
```
