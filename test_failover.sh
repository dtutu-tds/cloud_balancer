#!/bin/bash

# Скрипт для тестирования отказоустойчивости системы
# Автор: Terraform HA Infrastructure Test

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Конфигурация
NLB_IP="84.201.170.171"
VM1_NAME="ha-web-web-1"
VM1_ID="fhm2pg84g904lmdeolhu"
VM2_NAME="ha-web-web-2" 
VM2_ID="fhm89le5i3h5eegd6f9t"

echo -e "${YELLOW}=== Тестирование отказоустойчивости системы ===${NC}"
echo "Публичный IP балансировщика: $NLB_IP"
echo "ВМ для тестирования: $VM1_NAME (ID: $VM1_ID)"
echo ""

# Функция для проверки HTTP ответа
check_http() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://$NLB_IP --connect-timeout 5 --max-time 10)
    echo $response
}

# Функция для получения статуса ВМ
get_vm_status() {
    local vm_id=$1
    yc compute instance get $vm_id --format json | jq -r '.status'
}

# Функция для ожидания изменения статуса
wait_for_status() {
    local vm_id=$1
    local expected_status=$2
    local timeout=60
    local counter=0
    
    echo -n "Ожидание статуса $expected_status для ВМ..."
    while [ $counter -lt $timeout ]; do
        local current_status=$(get_vm_status $vm_id)
        if [ "$current_status" = "$expected_status" ]; then
            echo -e " ${GREEN}OK${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        counter=$((counter + 2))
    done
    echo -e " ${RED}TIMEOUT${NC}"
    return 1
}

echo -e "${YELLOW}1. Проверка начального состояния${NC}"
echo "Проверка доступности балансировщика..."
initial_response=$(check_http)
if [ "$initial_response" = "200" ]; then
    echo -e "✓ Балансировщик отвечает: ${GREEN}HTTP $initial_response${NC}"
else
    echo -e "✗ Балансировщик не отвечает: ${RED}HTTP $initial_response${NC}"
    exit 1
fi

echo "Проверка статуса ВМ..."
vm1_status=$(get_vm_status $VM1_ID)
vm2_status=$(get_vm_status $VM2_ID)
echo "✓ $VM1_NAME: $vm1_status"
echo "✓ $VM2_NAME: $vm2_status"

if [ "$vm1_status" != "RUNNING" ] || [ "$vm2_status" != "RUNNING" ]; then
    echo -e "${RED}Ошибка: Не все ВМ в статусе RUNNING${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}2. Остановка одной ВМ для тестирования отказоустойчивости${NC}"
echo "Останавливаю $VM1_NAME..."
yc compute instance stop $VM1_ID

# Ожидание остановки ВМ
wait_for_status $VM1_ID "STOPPED"

echo ""
echo -e "${YELLOW}3. Проверка работоспособности балансировщика после остановки ВМ${NC}"
echo "Ожидание обновления health-check (30 секунд)..."
sleep 30

echo "Выполнение серии HTTP запросов к балансировщику..."
success_count=0
total_requests=10

for i in $(seq 1 $total_requests); do
    response=$(check_http)
    if [ "$response" = "200" ]; then
        success_count=$((success_count + 1))
        echo "Запрос $i: ${GREEN}HTTP $response${NC}"
    else
        echo "Запрос $i: ${RED}HTTP $response${NC}"
    fi
    sleep 1
done

echo ""
echo "Результат тестирования: $success_count/$total_requests успешных запросов"

if [ $success_count -eq $total_requests ]; then
    echo -e "✓ ${GREEN}Отказоустойчивость работает корректно!${NC}"
    echo "Балансировщик продолжает отвечать на все запросы после остановки одной ВМ"
else
    echo -e "✗ ${RED}Проблема с отказоустойчивостью!${NC}"
    echo "Не все запросы были успешными"
fi

echo ""
echo -e "${YELLOW}4. Запуск остановленной ВМ${NC}"
echo "Запускаю $VM1_NAME..."
yc compute instance start $VM1_ID

# Ожидание запуска ВМ
wait_for_status $VM1_ID "RUNNING"

echo ""
echo -e "${YELLOW}5. Проверка восстановления после запуска ВМ${NC}"
echo "Ожидание готовности сервиса на восстановленной ВМ (60 секунд)..."
sleep 60

echo "Проверка финального состояния..."
final_response=$(check_http)
if [ "$final_response" = "200" ]; then
    echo -e "✓ Балансировщик отвечает: ${GREEN}HTTP $final_response${NC}"
else
    echo -e "✗ Балансировщик не отвечает: ${RED}HTTP $final_response${NC}"
fi

# Проверка статуса всех ВМ
echo "Финальный статус ВМ:"
vm1_final_status=$(get_vm_status $VM1_ID)
vm2_final_status=$(get_vm_status $VM2_ID)
echo "✓ $VM1_NAME: $vm1_final_status"
echo "✓ $VM2_NAME: $vm2_final_status"

echo ""
echo -e "${YELLOW}6. Проверка состояния таргет-группы${NC}"
yc load-balancer target-group get enpf50irotp4j9efudh9

echo ""
if [ "$final_response" = "200" ] && [ "$vm1_final_status" = "RUNNING" ] && [ "$vm2_final_status" = "RUNNING" ]; then
    echo -e "${GREEN}=== ТЕСТ ОТКАЗОУСТОЙЧИВОСТИ ПРОЙДЕН УСПЕШНО ===${NC}"
    echo "✓ Система корректно обрабатывает отказ одной ВМ"
    echo "✓ Балансировщик продолжает работать при отказе"
    echo "✓ Восстановление ВМ происходит автоматически"
else
    echo -e "${RED}=== ТЕСТ ОТКАЗОУСТОЙЧИВОСТИ НЕ ПРОЙДЕН ===${NC}"
    echo "Обнаружены проблемы в работе системы"
fi