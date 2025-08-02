#cloud-config

# Обновление пакетов и установка Nginx
package_update: true
package_upgrade: true

packages:
  - nginx
  - curl

# Команды для настройки Nginx
runcmd:
  # Включаем автоматический запуск Nginx при старте системы (требование 4.3)
  - systemctl enable nginx
  # Запускаем Nginx сразу после установки (требование 4.1)
  - systemctl start nginx
  # Настраиваем firewall для HTTP трафика
  - ufw allow 'Nginx Full'
  - ufw allow OpenSSH
  # Создаем кастомную страницу с информацией о сервере (требование 4.2)
  - 'echo "<h1>Nginx Server: $(hostname)</h1><p>Server started at: $(date)</p><p>This server is part of HA infrastructure</p>" > /var/www/html/index.html'
  # Проверяем что Nginx запустился корректно
  - 'systemctl is-active nginx || (echo "ERROR: Nginx failed to start" >> /var/log/cloud-init-output.log && exit 1)'
  # Проверяем что Nginx отвечает на HTTP запросы
  - 'sleep 5 && curl -f http://localhost/ || (echo "ERROR: Nginx HTTP check failed" >> /var/log/cloud-init-output.log && exit 1)'

# Автоматический запуск Nginx настраивается через systemctl enable в runcmd

# Логирование процесса инициализации
output:
  all: ">> /var/log/cloud-init-output.log"

# Финальное сообщение
final_message: "Cloud-init setup completed successfully. Nginx is running and ready to serve HTTP requests."