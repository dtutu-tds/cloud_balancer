# Документ проектирования

## Обзор

Проект реализует отказоустойчивую инфраструктуру в Yandex Cloud с использованием Terraform. Архитектура включает две виртуальные машины с Nginx, объединенные в таргет-группу и обслуживаемые сетевым балансировщиком нагрузки с HTTP health-check.

## Архитектура

```
 ┌─────────────────┐        health-check        ┌──────────────────┐
 │  yandex_lb_…    │──────── HTTP :80 ────────▶│  yandex_compute  │
 │  Network LB     │                           │  instance.web[0] │
 │  (Public IP)    │◀──── traffic :80 ─────────┤   Nginx 80/tcp   │
 │  Listener :80   │                           └──────────────────┘
 │  Backend group  │
 │    ↑ targets    │                           ┌──────────────────┐
 │  yandex_lb_tg   │──────── HTTP :80 ────────▶│  yandex_compute  │
 └─────────────────┘                           │  instance.web[1] │
                                               │   Nginx 80/tcp   │
                                               └──────────────────┘
```

## Компоненты и интерфейсы

### 1. Сетевая инфраструктура (VPC)

**Компонент:** `yandex_vpc_network` и `yandex_vpc_subnet`
- Создает изолированную сетевую среду
- Определяет CIDR блок для подсети
- Привязывается к конкретной зоне доступности

**Интерфейсы:**
- Входные параметры: `cidr`, `zone`, `project_name`
- Выходные данные: `network_id`, `subnet_id`

### 2. Группа безопасности

**Компонент:** `yandex_vpc_security_group`
- Контролирует входящий и исходящий трафик
- Открывает порты 22 (SSH) и 80 (HTTP)

**Правила:**
- Ingress: 22/tcp (SSH), 80/tcp (HTTP)
- Egress: разрешен весь исходящий трафик

### 3. Виртуальные машины

**Компонент:** `yandex_compute_instance` с `count = var.instance_count`
- Создает масштабируемое количество идентичных ВМ
- Использует Ubuntu 22.04 LTS образ
- Конфигурация: 2 CPU, 2GB RAM, standard-v2

**Автоматизация установки:**
- Cloud-init скрипт для установки Nginx
- SSH ключи через metadata
- Публичные IP для упрощения доступа

### 4. Таргет-группа

**Компонент:** `yandex_lb_target_group`
- Динамически включает все созданные ВМ
- Использует `dynamic "target"` блок для автоматического добавления

**Логика:**
```hcl
dynamic "target" {
  for_each = yandex_compute_instance.web[*].network_interface[0].ip_address
  content {
    address   = target.value
    subnet_id = yandex_vpc_subnet.public.id
  }
}
```

### 5. Сетевой балансировщик нагрузки

**Компонент:** `yandex_lb_network_load_balancer`
- Слушает на порту 80
- Перенаправляет трафик на порт 80 целевых машин
- HTTP health-check на путь "/"

**Конфигурация health-check:**
- Протокол: HTTP
- Порт: 80
- Путь: "/"
- Интервал и таймауты по умолчанию

## Модели данных

### Переменные (variables.tf)

```hcl
variable "instance_count" {
  description = "Количество виртуальных машин"
  type        = number
  default     = 2
}

variable "yc_token" {
  description = "OAuth токен Yandex Cloud"
  type        = string
  sensitive   = true
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

variable "ssh_pub_key" {
  description = "Путь к публичному SSH ключу"
  type        = string
}

variable "project_name" {
  description = "Префикс имен ресурсов"
  type        = string
  default     = "ha-web"
}
```

### Выходные данные (outputs.tf)

```hcl
output "nlb_public_ip" {
  description = "Публичный IP балансировщика"
  value       = yandex_lb_network_load_balancer.nlb.listener[0].external_address_spec[0].address
}

output "web_private_ips" {
  description = "Внутренние IP адреса ВМ"
  value       = yandex_compute_instance.web[*].network_interface[0].ip_address
}

output "web_public_ips" {
  description = "Публичные IP адреса ВМ"
  value       = yandex_compute_instance.web[*].network_interface[0].nat_ip_address
}
```

## Обработка ошибок

### Сценарии отказов

1. **Недоступность одной ВМ:**
   - Health-check исключает неработающую ВМ из ротации
   - Трафик перенаправляется только на здоровые инстансы
   - Автоматическое восстановление при возвращении ВМ в строй

2. **Проблемы с cloud-init:**
   - Возможна задержка в установке Nginx
   - Health-check будет показывать unhealthy до завершения установки
   - Рекомендуется увеличить start-delay для health-check

3. **Сетевые проблемы:**
   - Security group правила защищают от несанкционированного доступа
   - NAT обеспечивает доступ в интернет для обновлений

### Мониторинг и диагностика

- Статус балансировщика в консоли YC
- Состояние целевых машин в таргет-группе
- Логи cloud-init: `/var/log/cloud-init-output.log`
- Статус Nginx: `systemctl status nginx`

## Стратегия тестирования

### Функциональное тестирование

1. **Проверка создания ресурсов:**
   - `terraform plan` - валидация конфигурации
   - `terraform apply` - создание инфраструктуры
   - Проверка статусов в консоли YC

2. **Тестирование доступности:**
   - HTTP запросы к публичному IP балансировщика
   - Проверка ответов от разных ВМ
   - Тестирование при отключении одной ВМ

3. **Тестирование отказоустойчивости:**
   - Остановка одной ВМ через `yc compute instance stop`
   - Проверка продолжения работы сервиса
   - Восстановление и проверка возврата ВМ в ротацию

### Автоматизированное тестирование

- Скрипты для проверки HTTP ответов
- Мониторинг health-check статусов
- Валидация Terraform конфигурации

## Масштабирование и развитие

### Горизонтальное масштабирование

- Изменение `instance_count` для добавления/удаления ВМ
- Автоматическое обновление таргет-группы
- Поддержка до 254 инстансов в подсети

### Улучшения архитектуры

1. **Мульти-зональность:**
   - Размещение ВМ в разных зонах доступности
   - Создание подсетей в каждой зоне
   - Повышение отказоустойчивости

2. **Application Load Balancer:**
   - Переход на L7 балансировщик для расширенных возможностей
   - SSL терминация
   - Более гибкие правила маршрутизации

3. **Мониторинг и алертинг:**
   - Интеграция с Yandex Monitoring
   - Настройка уведомлений о проблемах
   - Метрики производительности