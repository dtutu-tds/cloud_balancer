# Пример файла terraform.tfvars
# Скопируйте этот файл в terraform.tfvars и заполните своими значениями

# OAuth токен для доступа к Yandex Cloud
# Получить можно по ссылке: https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb
yc_token = "y0__xDkiqSaAhjB3RMg9ZmW_hMwmKulpAiWJVrfS8skSw39PeGajOk5XiVyeg"

# ID облака в Yandex Cloud
# Найти можно в консоли: https://console.cloud.yandex.ru/
cloud_id = "b1gmdn70g06hoq9n9f7c"

# ID папки в Yandex Cloud
folder_id = "b1gc0k8akffl633ichr0"

# Зона доступности (по умолчанию ru-central1-a)
zone = "ru-central1-a"

# CIDR блок для подсети (по умолчанию 10.0.1.0/24)
cidr = "10.128.0.0/24"

# Количество виртуальных машин (по умолчанию 2)
instance_count = 2

# Путь к публичному SSH ключу
# Создать можно командой: ssh-keygen -t rsa -b 2048 -f ~/.ssh/yc_key
ssh_pub_key = "~/.ssh/yc_key.pub"

# Префикс имен ресурсов (по умолчанию ha-web)
project_name = "ha-web"

# Параметры виртуальных машин
instance_cores = 2
instance_memory = 2
instance_disk_size = 20