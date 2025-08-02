# Выходные параметры Terraform конфигурации

output "nlb_public_ip" {
  description = "Публичный IP адрес сетевого балансировщика нагрузки"
  value       = [for listener in yandex_lb_network_load_balancer.nlb.listener : [for addr in listener.external_address_spec : addr.address][0]][0]
}

output "web_private_ips" {
  description = "Внутренние IP адреса веб-серверов"
  value       = yandex_compute_instance.web[*].network_interface[0].ip_address
}

output "web_public_ips" {
  description = "Публичные IP адреса веб-серверов"
  value       = yandex_compute_instance.web[*].network_interface[0].nat_ip_address
}

output "target_group_id" {
  description = "ID таргет-группы балансировщика"
  value       = yandex_lb_target_group.web.id
}

output "network_id" {
  description = "ID созданной VPC сети"
  value       = yandex_vpc_network.main.id
}

output "subnet_id" {
  description = "ID созданной подсети"
  value       = yandex_vpc_subnet.public.id
}