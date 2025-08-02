# Домашнее задание к занятию «Отказоустойчивость в облаке»

### Цель задания

В результате выполнения этого задания вы научитесь:  
1. Конфигурировать отказоустойчивый кластер в облаке с использованием различных функций отказоустойчивости. 
2. Устанавливать сервисы из конфигурации инфраструктуры.

------

### Чеклист готовности к домашнему заданию

1. Создан аккаунт на YandexCloud.  
2. Создан новый OAuth-токен.  
3. Установлено программное обеспечение  Terraform.   


### Инструкция по выполнению домашнего задания

1. Сделайте fork [репозитория c Шаблоном решения](https://github.com/netology-code/sys-pattern-homework) к себе в Github и переименуйте его по названию или номеру занятия, например, https://github.com/имя-вашего-репозитория/gitlab-hw или https://github.com/имя-вашего-репозитория/8-03-hw).
2. Выполните клонирование данного репозитория к себе на ПК с помощью команды `git clone`.
3. Выполните домашнее задание и заполните у себя локально этот файл README.md:
   - впишите вверху название занятия и вашу фамилию и имя
   - в каждом задании добавьте решение в требуемом виде (текст/код/скриншоты/ссылка)
   - для корректного добавления скриншотов воспользуйтесь инструкцией ["Как вставить скриншот в шаблон с решением"](https://github.com/netology-code/sys-pattern-homework/blob/main/screen-instruction.md)
   - при оформлении используйте возможности языка разметки md (коротко об этом можно посмотреть в [инструкции по MarkDown](https://github.com/netology-code/sys-pattern-homework/blob/main/md-instruction.md))
4. После завершения работы над домашним заданием сделайте коммит (`git commit -m "comment"`) и отправьте его на Github (`git push origin`);
5. Для проверки домашнего задания преподавателем в личном кабинете прикрепите и отправьте ссылку на решение в виде md-файла в вашем Github.
6. Любые вопросы по выполнению заданий спрашивайте в чате учебной группы и/или в разделе "Вопросы по заданию" в личном кабинете.


### Инструменты и дополнительные материалы, которые пригодятся для выполнения задания

1. [Документация сетевого балансировщика нагрузки](https://cloud.yandex.ru/docs/network-load-balancer/quickstart)

 ---

## Задание 1 

Возьмите за основу [решение к заданию 1 из занятия «Подъём инфраструктуры в Яндекс Облаке»](https://github.com/netology-code/sdvps-homeworks/blob/main/7-03.md#задание-1).

1. Теперь вместо одной виртуальной машины сделайте terraform playbook, который:

- создаст 2 идентичные виртуальные машины. Используйте аргумент [count](https://www.terraform.io/docs/language/meta-arguments/count.html) для создания таких ресурсов;
- создаст [таргет-группу](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/lb_target_group). Поместите в неё созданные на шаге 1 виртуальные машины;
- создаст [сетевой балансировщик нагрузки](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/lb_network_load_balancer), который слушает на порту 80, отправляет трафик на порт 80 виртуальных машин и http healthcheck на порт 80 виртуальных машин.

Рекомендуем изучить [документацию сетевого балансировщика нагрузки](https://cloud.yandex.ru/docs/network-load-balancer/quickstart) для того, чтобы было понятно, что вы сделали.

2. Установите на созданные виртуальные машины пакет Nginx любым удобным способом и запустите Nginx веб-сервер на порту 80.

3. Перейдите в веб-консоль Yandex Cloud и убедитесь, что: 

- созданный балансировщик находится в статусе Active,
- обе виртуальные машины в целевой группе находятся в состоянии healthy.

4. Сделайте запрос на 80 порт на внешний IP-адрес балансировщика и убедитесь, что вы получаете ответ в виде дефолтной страницы Nginx.

*В качестве результата пришлите:*

*1. Terraform Playbook.*

*2. Скриншот статуса балансировщика и целевой группы.*

*3. Скриншот страницы, которая открылась при запросе IP-адреса балансировщика.*

---

## Решение

### 1. Terraform Playbook

Проект состоит из следующих файлов:

#### main.tf
```hcl
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

# Создание VPC сети
resource "yandex_vpc_network" "network" {
  name = "${var.project_name}-network"
}

# Создание подсети
resource "yandex_vpc_subnet" "public" {
  name           = "${var.project_name}-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = [var.cidr]
}

# Создание группы безопасности
resource "yandex_vpc_security_group" "web_sg" {
  name       = "${var.project_name}-sg"
  network_id = yandex_vpc_network.network.id

  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "All outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Создание виртуальных машин
resource "yandex_compute_instance" "web" {
  count = var.instance_count
  name  = "${var.project_name}-${count.index + 1}"
  zone  = var.zone

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8kdq6d0p8sij7h5qe3"  # Ubuntu 22.04 LTS
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.web_sg.id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl", {
      ssh_public_key = file(var.ssh_pub_key)
    })
  }
}

# Создание таргет-группы
resource "yandex_lb_target_group" "web_tg" {
  name = "${var.project_name}-tg"

  dynamic "target" {
    for_each = yandex_compute_instance.web[*].network_interface[0].ip_address
    content {
      address   = target.value
      subnet_id = yandex_vpc_subnet.public.id
    }
  }
}

# Создание сетевого балансировщика нагрузки
resource "yandex_lb_network_load_balancer" "nlb" {
  name = "${var.project_name}-nlb"

  listener {
    name = "web-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.web_tg.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
```

#### variables.tf
```hcl
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

variable "ssh_pub_key" {
  description = "Путь к публичному SSH ключу"
  type        = string
}

variable "project_name" {
  description = "Префикс имен ресурсов"
  type        = string
  default     = "ha-web"
}

variable "instance_count" {
  description = "Количество виртуальных машин"
  type        = number
  default     = 2
}
```

#### outputs.tf
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

#### cloud-init.tpl
```yaml
#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
package_upgrade: true

packages:
  - nginx

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - ufw allow 'Nginx Full'
  - ufw allow OpenSSH
  - echo "Web server $(hostname) is running" > /var/www/html/index.html
```

### 2. Команды для создания скриншотов

Для выполнения задания и создания необходимых скриншотов используйте следующие команды:

#### Инициализация и применение Terraform:
```bash
# Инициализация Terraform
terraform init

# Проверка плана выполнения
terraform plan

# Применение конфигурации
terraform apply
```

#### Получение информации о созданных ресурсах:
```bash
# Получить публичный IP балансировщика
terraform output nlb_public_ip

# Получить все выходные данные
terraform output
```

#### Тестирование HTTP доступности:
```bash
# Получить публичный IP балансировщика
NLB_IP=$(terraform output -raw nlb_public_ip)

# Выполнить HTTP запрос к балансировщику
curl http://$NLB_IP

# Выполнить несколько запросов для проверки балансировки
for i in {1..5}; do curl http://$NLB_IP; echo; done
```

#### Тестирование отказоустойчивости:
```bash
# Получить список ВМ
yc compute instance list

# Остановить одну из ВМ (замените INSTANCE_ID на реальный ID)
yc compute instance stop INSTANCE_ID

# Проверить, что балансировщик продолжает работать
curl http://$NLB_IP

# Запустить ВМ обратно
yc compute instance start INSTANCE_ID
```

#### Команды для проверки статуса в консоли YC:
```bash
# Проверить статус балансировщика
yc load-balancer network-load-balancer list

# Проверить статус таргет-группы
yc load-balancer target-group list

# Проверить статус ВМ
yc compute instance list
```

### 3. Скриншоты

**Внимание!** В проекте отсутствует папка `screenshots`. Для корректного оформления домашнего задания необходимо:

1. Создать папку `screenshots` в корне проекта:
   ```bash
   mkdir screenshots
   ```

2. Сделать следующие скриншоты и поместить их в папку `screenshots`:
   - `nlb_status.png` - статус балансировщика в консоли Yandex Cloud
   - `target_group_status.png` - статус целевой группы с healthy машинами
   - `nginx_page.png` - страница Nginx, открытая по IP балансировщика
   - `terraform_output.png` - вывод команды `terraform output`

3. Добавить ссылки на скриншоты в этот README.md:
   ```markdown
   ![Статус балансировщика](screenshots/nlb_status.png)
   ![Статус целевой группы](screenshots/target_group_status.png)
   ![Страница Nginx](screenshots/nginx_page.png)
   ![Вывод Terraform](screenshots/terraform_output.png)
   ```

### 4. Верификация инфраструктуры

В проекте также созданы скрипты для автоматической верификации:

- `verify_infrastructure.sh` - проверка статуса всех компонентов
- `test_http_availability.sh` - тестирование HTTP доступности
- `test_failover.sh` - тестирование отказоустойчивости

Запустите их для проверки работоспособности инфраструктуры:

```bash
# Проверка инфраструктуры
./verify_infrastructure.sh

# Тестирование HTTP доступности
./test_http_availability.sh

# Тестирование отказоустойчивости
./test_failover.sh
```

### 5. Очистка ресурсов

После завершения тестирования не забудьте удалить созданные ресурсы:

```bash
terraform destroy
```

---

## Заключение

Проект успешно реализует отказоустойчивую инфраструктуру в Yandex Cloud с использованием:
- Двух идентичных виртуальных машин с Nginx
- Таргет-группы для объединения ВМ
- Сетевого балансировщика нагрузки с HTTP health-check
- Автоматической установки и настройки Nginx через cloud-init

Инфраструктура обеспечивает высокую доступность веб-сервиса и автоматическое исключение неработающих инстансов из ротации.