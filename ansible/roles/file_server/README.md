# Role `file_server`

File server and DFS namespace server (issue #9), on `hq-fs01`. It is driven by
`playbooks/file-server.yml`, which first joins the server (role `domain_member`) and creates the
AGDLP identities on the forest root DC (role `ad_identities`). The data is `fs_shares` and
`ad_role_groups` in `group_vars/all.yml`.

| Layer | What |
| --- | --- |
| Volume | `D:` (label Data) on its own disk (`scsi1` in Terraform). The cloud-init config drive is moved from D: to Z:; cloudbase-init finds it by label |
| NTFS | `D:\Shares\<name>`: inheritance removed. Only SYSTEM, Administrators and `DL-FS-<name>-RW` (Modify) / `-RO` (ReadAndExecute) |
| SMB | One share per folder: Authenticated Users Change and Administrators Full at share level (NTFS decides), access-based enumeration on, offline caching off |
| DFS-N | Domain-based (V2) `\\corp.huylab.internal\Shares` with ABE. Each folder has explicit DFS permissions for its DL groups, so a user only *sees* what they can open |

AGDLP chain: user → `G-<role>` (OU=Roles) → `DL-FS-<share>-RW/RO` (OU=Resources) → NTFS. To
change what someone can access, change their G membership; never grant to users directly.

Proof: `scripts/fs-access-test.sh` → `docs/fileserver/access-test-report.md`. It uses real domain
users over SMB 3 through the namespace, from both sites. A deny must be an explicit SMB answer.

## Pitfalls found while building it

1. Server Core has no `RSAT-DFS-Mgmt-Con` (the GUI console). The DFSN PowerShell module comes
   with `FS-DFS-Namespace` plus `include_management_tools`.
2. The cloud-init config drive takes `D:` on the first boot, so it is moved to Z: before the
   data volume is created. The disk detection also accepts a GPT disk that is still empty,
   which is what an interrupted run leaves behind.
