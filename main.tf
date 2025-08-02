# Terraform конфигурация для отказоустойчивой инфраструктуры в Yandex Cloud

terraform {
  required_version = ">= 1.0"
  required_providers {
    yandex = {
      source  = "local/yandex-cloud/yandex"
      version = "0.147.0"
    }
  }
}

# Провайдер Yandex Cloud
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

# Создание VPC сети
resource "yandex_vpc_network" "main" {
  name        = "${var.project_name}-network"
  description = "Основная сеть для ${var.project_name} проекта"
}

# Создание подсети
resource "yandex_vpc_subnet" "public" {
  name           = "${var.project_name}-subnet"
  description    = "Публичная подсеть для ${var.project_name} проекта"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.cidr]
}

# Создание группы безопасности
resource "yandex_vpc_security_group" "web" {
  name        = "${var.project_name}-security-group"
  description = "Группа безопасности для веб-серверов"
  network_id  = yandex_vpc_network.main.id

  # Правило для входящего SSH трафика
  ingress {
    description    = "SSH"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Правило для входящего HTTP трафика
  ingress {
    description    = "HTTP"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Правило для исходящего трафика (разрешить весь)
  egress {
    description    = "All outbound traffic"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Получение актуального образа Ubuntu 22.04 LTS
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# Создание виртуальных машин с использованием count
resource "yandex_compute_instance" "web" {
  count       = var.instance_count
  name        = "${var.project_name}-web-${count.index + 1}"
  description = "Веб-сервер ${count.index + 1} для ${var.project_name} проекта"
  zone        = var.zone

  # Конфигурация ресурсов ВМ (требование: CPU, память, диск)
  resources {
    cores         = var.instance_cores
    memory        = var.instance_memory
    core_fraction = 100
  }

  # Конфигурация загрузочного диска с образом Ubuntu 22.04
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.instance_disk_size
      type     = "network-hdd"
    }
  }

  # Сетевая конфигурация
  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.web.id]
    nat                = true  # Назначение публичного IP для SSH доступа
  }

  # Интеграция cloud-init скрипта через metadata
  metadata = {
    # Настройка SSH доступа через публичные ключи
    ssh-keys = "ubuntu:${file(var.ssh_pub_key)}"
    # Подключение cloud-init скрипта для автоматической установки Nginx
    user-data = file("${path.module}/cloud-init.tpl")
  }

  # Настройки планировщика
  scheduling_policy {
    preemptible = false  # Не использовать прерываемые ВМ для стабильности
  }

  # Теги для идентификации ресурсов
  labels = {
    project     = var.project_name
    environment = "production"
    role        = "web-server"
    instance    = tostring(count.index + 1)
  }
}

# Создание таргет-группы для балансировщика нагрузки
resource "yandex_lb_target_group" "web" {
  name        = "${var.project_name}-target-group"
  description = "Таргет-группа для веб-серверов ${var.project_name} проекта"
  region_id   = "ru-central1"

  # Динамическое добавление всех созданных ВМ в таргет-группу
  dynamic "target" {
    for_each = yandex_compute_instance.web[*].network_interface[0].ip_address
    content {
      address   = target.value
      subnet_id = yandex_vpc_subnet.public.id
    }
  }

  # Теги для идентификации ресурса
  labels = {
    project     = var.project_name
    environment = "production"
    role        = "load-balancer-target-group"
  }
}

# Создание сетевого балансировщика нагрузки (NLB)
resource "yandex_lb_network_load_balancer" "nlb" {
  name        = "${var.project_name}-nlb"
  description = "Сетевой балансировщик нагрузки для ${var.project_name} проекта"
  type        = "external"
  region_id   = "ru-central1"

  # Настройка listener на порту 80
  listener {
    name        = "http-listener"
    port        = 80
    protocol    = "tcp"
    target_port = 80

    # Настройка внешнего адреса (публичный IP)
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  # Подключение созданной таргет-группы
  attached_target_group {
    target_group_id = yandex_lb_target_group.web.id

    # Настройка HTTP health-check на путь "/" порт 80
    healthcheck {
      name                = "http-health-check"
      interval            = 2   # Интервал проверки в секундах
      timeout             = 1   # Таймаут проверки в секундах
      unhealthy_threshold = 2   # Количество неудачных проверок для признания unhealthy
      healthy_threshold   = 2   # Количество успешных проверок для признания healthy

      # HTTP проверка здоровья
      http_options {
        port = 80
        path = "/"
      }
    }
  }

  # Теги для идентификации ресурса
  labels = {
    project     = var.project_name
    environment = "production"
    role        = "network-load-balancer"
  }
}