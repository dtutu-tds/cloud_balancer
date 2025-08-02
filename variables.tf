# Переменные для Terraform конфигурации

variable "yc_token" {
  description = "OAuth токен Yandex Cloud"
  type        = string
  sensitive   = true
}

variable "cloud_id" {
  description = "ID облака в Yandex Cloud"
  type        = string
}

variable "folder_id" {
  description = "ID папки в Yandex Cloud"
  type        = string
}

variable "zone" {
  description = "Зона доступности"
  type        = string
  default     = "ru-central1-a"
}

variable "cidr" {
  description = "CIDR блок для подсети"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_count" {
  description = "Количество виртуальных машин"
  type        = number
  default     = 2
  
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Количество инстансов должно быть от 1 до 10."
  }
}

variable "ssh_pub_key" {
  description = "Путь к публичному SSH ключу"
  type        = string
}

variable "project_name" {
  description = "Префикс имен ресурсов"
  type        = string
  default     = "ha-web"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Имя проекта должно содержать только строчные буквы, цифры и дефисы."
  }
}

variable "instance_cores" {
  description = "Количество CPU ядер для ВМ"
  type        = number
  default     = 2
}

variable "instance_memory" {
  description = "Объем памяти для ВМ в ГБ"
  type        = number
  default     = 2
}

variable "instance_disk_size" {
  description = "Размер диска для ВМ в ГБ"
  type        = number
  default     = 20
}