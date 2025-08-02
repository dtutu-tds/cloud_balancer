#!/bin/bash

# Скрипт для верификации созданной инфраструктуры в Yandex Cloud
# Задача 9: Верификация созданной инфраструктуры в консоли YC

echo "=== ВЕРИФИКАЦИЯ ИНФРАСТРУКТУРЫ YANDEX CLOUD ==="
echo "Дата проверки: $(date)"
echo

# Получаем данные из Terraform outputs
NLB_IP=$(terraform output -raw nlb_public_ip)
WEB_PRIVATE_IPS=($(terraform output -json web_private_ips | jq -r '.[]'))
WEB_PUBLIC_IPS=($(terraform output -json web_public_ips | jq -r '.[]'))
TARGET_GROUP_ID=$(terraform output -raw target_group_id)

echo "Публичный IP балансировщика: $NLB_IP"
echo "Приватные IP ВМ: ${WEB_PRIVATE_IPS[*]}"
echo "Публичные IP ВМ: ${WEB_PUBLIC_IPS[*]}"
echo "ID таргет-группы: $TARGET_GROUP_ID"
echo

# 1. Проверка статуса виртуальных машин (требование 1.2)
echo "=== 1. ПРОВЕРКА СТАТУСА ВИРТУАЛЬНЫХ МАШИН ==="
echo "Проверяем доступность ВМ через SSH и статус Nginx..."

for i in "${!WEB_PUBLIC_IPS[@]}"; do
    VM_IP=${WEB_PUBLIC_IPS[$i]}
    VM_PRIVATE_IP=${WEB_PRIVATE_IPS[$i]}
    echo
    echo "ВМ $((i+1)): $VM_IP (приватный: $VM_PRIVATE_IP)"
    
    # Проверяем SSH доступность
    echo -n "  SSH доступность: "
    if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$VM_IP "echo 'OK'" 2>/dev/null; then
        echo "✓ ДОСТУПНА"
        
        # Проверяем статус Nginx
        echo -n "  Статус Nginx: "
        NGINX_STATUS=$(timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$VM_IP "systemctl is-active nginx" 2>/dev/null)
        if [ "$NGINX_STATUS" = "active" ]; then
            echo "✓ ACTIVE (RUNNING)"
        else
            echo "✗ НЕ АКТИВЕН ($NGINX_STATUS)"
        fi
        
        # Проверяем HTTP ответ локально на ВМ
        echo -n "  HTTP ответ (локально): "
        HTTP_LOCAL=$(timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$VM_IP "curl -s -o /dev/null -w '%{http_code}' http://localhost/" 2>/dev/null)
        if [ "$HTTP_LOCAL" = "200" ]; then
            echo "✓ HTTP 200"
        else
            echo "✗ HTTP $HTTP_LOCAL"
        fi
        
    else
        echo "✗ НЕДОСТУПНА"
    fi
done

echo
echo "=== 2. ПРОВЕРКА СТАТУСА БАЛАНСИРОВЩИКА ==="
echo "Проверяем доступность балансировщика и HTTP ответы..."

# Проверяем HTTP ответ от балансировщика
echo -n "HTTP ответ от балансировщика ($NLB_IP): "
NLB_HTTP_CODE=$(timeout 15 curl -s -o /dev/null -w '%{http_code}' http://$NLB_IP/ 2>/dev/null)
if [ "$NLB_HTTP_CODE" = "200" ]; then
    echo "✓ HTTP 200 - БАЛАНСИРОВЩИК АКТИВЕН"
    
    # Получаем содержимое страницы для проверки
    echo "Содержимое страницы:"
    timeout 15 curl -s http://$NLB_IP/ 2>/dev/null | head -3
    
else
    echo "✗ HTTP $NLB_HTTP_CODE - ПРОБЛЕМА С БАЛАНСИРОВЩИКОМ"
fi

echo
echo "=== 3. ПРОВЕРКА HEALTH-CHECK СТАТУСА ==="
echo "Проверяем доступность каждой ВМ через балансировщик..."

# Делаем несколько запросов для проверки распределения нагрузки
echo "Выполняем 10 запросов для проверки распределения нагрузки:"
for i in {1..10}; do
    echo -n "Запрос $i: "
    RESPONSE=$(timeout 10 curl -s http://$NLB_IP/ 2>/dev/null)
    if echo "$RESPONSE" | grep -q "Nginx Server"; then
        # Извлекаем hostname из ответа
        HOSTNAME=$(echo "$RESPONSE" | grep -o 'Nginx Server: [^<]*' | cut -d' ' -f3)
        echo "✓ Ответ от $HOSTNAME"
    else
        echo "✗ Некорректный ответ"
    fi
done

echo
echo "=== 4. ПРОВЕРКА TERRAFORM STATE ==="
echo "Проверяем состояние ресурсов в Terraform state..."

# Проверяем статус ресурсов в Terraform state
echo -n "Статус ВМ в Terraform: "
VM_STATUS_1=$(terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="yandex_compute_instance" and .index==0) | .values.status')
VM_STATUS_2=$(terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="yandex_compute_instance" and .index==1) | .values.status')

if [ "$VM_STATUS_1" = "running" ] && [ "$VM_STATUS_2" = "running" ]; then
    echo "✓ Обе ВМ в статусе RUNNING"
else
    echo "✗ ВМ1: $VM_STATUS_1, ВМ2: $VM_STATUS_2"
fi

echo -n "Статус балансировщика в Terraform: "
NLB_CREATED=$(terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="yandex_lb_network_load_balancer") | .values.created_at')
if [ "$NLB_CREATED" != "null" ] && [ -n "$NLB_CREATED" ]; then
    echo "✓ Балансировщик создан ($NLB_CREATED)"
else
    echo "✗ Проблема с балансировщиком"
fi

echo
echo "=== ИТОГОВАЯ СВОДКА ==="
echo "Публичный IP балансировщика: $NLB_IP"
echo "Количество ВМ: ${#WEB_PUBLIC_IPS[@]}"
echo "Статус проверки завершен: $(date)"

# Проверяем соответствие требованиям
echo
echo "=== СООТВЕТСТВИЕ ТРЕБОВАНИЯМ ==="
echo "Требование 1.2 (ВМ в статусе RUNNING): проверено выше"
echo "Требование 3.1 (Балансировщик Active): проверено через HTTP ответы"
echo "Требование 3.2 (ВМ в таргет-группе healthy): проверено через распределение нагрузки"
echo
echo "Для полной верификации в консоли YC используйте:"
echo "yc compute instance list --folder-id b1gc0k8akffl633ichr0"
echo "yc load-balancer network-load-balancer list --folder-id b1gc0k8akffl633ichr0"
echo "yc load-balancer target-group list --folder-id b1gc0k8akffl633ichr0"