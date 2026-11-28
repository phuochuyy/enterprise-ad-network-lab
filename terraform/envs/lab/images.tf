# Installer media, downloaded by the Proxmox host itself (download-url API), so
# nothing large passes through the workstation and versions are pinned in code.
#
# Integrity: SHA-256 where the vendor publishes one (OPNsense, Ubuntu). Microsoft
# evaluation media and virtio-win publish no ISO checksum; they are fetched over
# HTTPS from the vendor CDN and their hashes are recorded in docs/images.md after download.
locals {
  images = {
    ws2022 = {
      content_type = "iso"
      file_name    = "SERVER_EVAL_x64FRE_en-us_2022.iso"
      url          = "https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
      checksum     = null
      decompress   = null
    }
    win11 = {
      content_type = "iso"
      file_name    = "Win11_24H2_Enterprise_Eval_x64_en-us.iso"
      url          = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
      checksum     = null
      decompress   = null
    }
    virtio = {
      content_type = "iso"
      file_name    = "virtio-win-0.1.302.iso"
      url          = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso"
      checksum     = null
      decompress   = null
      timeout      = 7200 # fedorapeople.org serves ~270 KB/s; 0.9 GB timed out at 1 h
    }
    opnsense = {
      content_type = "iso"
      file_name    = "OPNsense-26.7-dvd-amd64.iso"
      url          = "https://pkg.opnsense.org/releases/mirror/OPNsense-26.7-dvd-amd64.iso.bz2"
      checksum     = "95cafedda6d5b22ce832e249dc2309110fbee19f813ad78cf28bb3d387186bfb" # of the .bz2
      decompress   = "bz2"
    }
    ubuntu2404 = {
      # Cloud image imported as a disk (PVE 9 "import" content) - no Packer build needed for Linux.
      content_type = "import"
      file_name    = "noble-server-cloudimg-amd64-20261017.qcow2"
      url          = "https://cloud-images.ubuntu.com/noble/20261017/noble-server-cloudimg-amd64.img"
      checksum     = "04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94"
      decompress   = null
    }
  }
}

resource "proxmox_download_file" "image" {
  for_each = local.images

  node_name               = var.node_name
  datastore_id            = "local"
  content_type            = each.value.content_type
  file_name               = each.value.file_name
  url                     = each.value.url
  checksum                = each.value.checksum
  checksum_algorithm      = each.value.checksum == null ? null : "sha256"
  decompression_algorithm = each.value.decompress
  upload_timeout          = try(each.value.timeout, 3600) # 5 GB over the host's Wi-Fi
  overwrite               = false
}
