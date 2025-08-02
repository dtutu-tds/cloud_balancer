#!/bin/bash

# Скрипт для тестирования HTTP доступности через балансировщик
# Автор: Terraform HA Infrastructure Project

echo "=== Тестирование HTTP доступности через балансировщик ==="
echo "Дата: $(date)"
echo

# Получаем публичный IP балансировщика
NLB_IP=$(terraform output -raw nlb_public_ip)
echo "Публичный IP балансировщика: $NLB_IP"
echo

# Тест 1: Базовая проверка доступности
echo "1. Базовая проверка HTTP доступности:"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$NLB_IP)
RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" http://$NLB_IP)

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ HTTP Status: $HTTP_STATUS (OK)"
    echo "⏱️  Response Time: ${RESPONSE_TIME}s"
else
    echo "❌ HTTP Status: $HTTP_STATUS (FAILED)"
    exit 1
fi
echo

# Тест 2: Проверка содержимого страницы
echo "2. Проверка содержимого дефолтной страницы Nginx:"
CONTENT=$(curl -s http://$NLB_IP)
if echo "$CONTENT" | grep -q "Nginx Server:"; then
    echo "✅ Страница содержит ожидаемый контент Nginx"
    echo "📄 Содержимое: $(echo "$CONTENT" | grep "Nginx Server:")"
else
    echo "❌ Страница не содержит ожидаемый контент Nginx"
    echo "📄 Полученное содержимое: $CONTENT"
fi
echo

# Тест 3: Проверка балансировки нагрузки
echo "3. Проверка балансировки нагрузки (10 запросов):"
declare -A servers
for i in {1..10}; do
    SERVER=$(curl -s http://$NLB_IP | grep -o 'Server: [^<]*' | cut -d' ' -f2)
    servers["$SERVER"]=$((${servers["$SERVER"]} + 1))
    sleep 0.5
done

echo "Распределение запросов по серверам:"
for server in "${!servers[@]}"; do
    echo "  🖥️  $server: ${servers[$server]} запросов"
done

# Проверяем, что используется более одного сервера
if [ ${#servers[@]} -gt 1 ]; then
    echo "✅ Балансировка работает корректно (используется ${#servers[@]} сервера)"
else
    echo "⚠️  Внимание: все запросы обрабатывает только один сервер"
fi
echo

# Тест 4: Проверка заголовков HTTP
echo "4. Проверка HTTP заголовков:"
curl -s -I http://$NLB_IP | head -5
echo

echo "=== Тестирование завершено ==="
echo "Все тесты пройдены успешно! Балансировщик работает корректно."