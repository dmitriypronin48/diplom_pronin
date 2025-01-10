resource "yandex_compute_disk" "boot-disk" {
  for_each = var.virtual_machines
  name     = each.value["disk_name"]
  type     = each.value["disk_type"]
  zone     = each.value["zone"]
  size     = each.value["disk"]
  image_id = each.value["template"]
}

resource "yandex_vpc_network" "network-1" {
  name = "network-1"
}

resource "yandex_vpc_gateway" "private_net" {
  name = "private-net-nat"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "route_with_nat" {
  network_id = "${yandex_vpc_network.network-1.id}"

  static_route {
    destination_prefix = "192.168.50.0/24"
    next_hop_address   = "192.168.30.1"
  }

  static_route {
    destination_prefix = "192.168.60.0/24"
    next_hop_address   = "192.168.30.1"
  }

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = "${yandex_vpc_gateway.private_net.id}"
  }
}

resource "yandex_vpc_subnet" "subnet" {
  for_each       = var.subnets
  name           = each.value["name"]
  zone           = each.value["zone"]
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = each.value["v4_cidr_blocks"]
  route_table_id = yandex_vpc_route_table.route_with_nat.id
}

resource "yandex_compute_instance" "virtual_machine" {
  for_each        = var.virtual_machines
  name = each.value["vm_name"]
  zone = each.value["zone"]
  allow_stopping_for_update = true

  platform_id = each.value["platform_id"]
  resources {
    cores  = each.value["vm_cpu"]
    memory = each.value["ram"]
    core_fraction = each.value["core_fraction"]
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk[each.key].id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet[each.value.subnet].id
    nat       = each.value["public_ip"]
  }

  metadata = {
    ssh-keys = "dmitriy_pronin:${file("~/.ssh/id_ed25519.pub")}"
  }
}

resource "yandex_lb_target_group" "nlb-group" {
  name      = "nlb-group-1"
  region_id = "ru-central1"

  target {
    subnet_id = yandex_vpc_subnet.subnet["s-1"].id
    address   = yandex_compute_instance.virtual_machine["vm-1"].network_interface.0.ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.subnet["s-2"].id
    address   = yandex_compute_instance.virtual_machine["vm-2"].network_interface.0.ip_address
  }
}

resource "yandex_lb_network_load_balancer" "nlb" {
  name = "nlb"

  listener {
    name = "http"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.nlb-group.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

resource "yandex_compute_snapshot" "disk-snap" {
  for_each = var.virtual_machines
  name     = each.value["disk_name"]
  source_disk_id = yandex_compute_disk.boot-disk[each.key].id
}

resource "yandex_compute_snapshot_schedule" "one_week_ttl_every_day" {
  for_each = var.virtual_machines
  name     = each.value["disk_name"]

  schedule_policy {
        expression = "0 0 * * *"
  }

  snapshot_count = 7
  retention_period = "168h"

  disk_ids = ["${yandex_compute_disk.boot-disk[each.key].id}"]
}
